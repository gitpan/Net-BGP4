package Net::BGP4::Process;

use strict;
use vars qw( $VERSION );

## Inheritance and Versioning ##

$VERSION = '0.01';

## Module Imports ##

use IO::Select;
use IO::Socket;
use Net::BGP4::Peer qw( BGP_PORT TRUE FALSE );

## Socket Constants ##

sub LISTEN_QUEUE_SIZE { 5 }

## Public Methods ##

sub new
{
    my $class = shift();
    my ($arg, $value);

    my $this = {
        _read_fh       => new IO::Select(),
        _write_fh      => new IO::Select(),
        _error_fh      => new IO::Select(),
        _peer_list     => {},
        _peer_addr     => {},
        _peer_sock     => {},
        _peer_sock_fh  => {},
        _peer_sock_map => {},
        _listen_socket => undef,
        _listen_port   => BGP_PORT
    };

    while ( defined($arg = shift()) ) {
        $value = shift();
        if ( $arg =~ /port/i ) {
            $this->{_listen_port} = $value;
        }
    }

    bless($this, $class);

    return ( $this );
}

sub add_peer
{
    my ($this, $peer) = @_;

    if ( ! defined($this->{_peer_addr}->{$peer->{_peer_id}}) ) {
        $this->{_peer_addr}->{$peer->{_peer_id}} = $peer;
        $this->{_peer_list}->{$peer} = $peer;
    }
}

sub remove_peer
{
    my ($this, $peer) = @_;

    if ( defined($this->{_peer_list}->{$peer}) ) {
        $peer->stop();
        $this->_update_select($peer);
        delete $this->{_peer_addr}->{$peer->{_peer_id}};
        delete $this->{_peer_list}->{$peer};
    }
}

sub event_loop
{
    my $this = shift();
    my ($time, $last_time, $delta, $min, $min_timer);
    my ($peer, $ready, @ready);
    my ($timer);

    # Poll each peer and create listen socket if any is a listener
    foreach $peer ( values(%{$this->{_peer_list}}) ) {
        if ( $peer->_is_listener() ) {
            $this->_init_listen_socket();
            last;
        }
    }

    while ( scalar(keys(%{$this->{_peer_list}})) ) {

        # Process timeouts, events, etc.
        $min_timer = 2147483647;
        $time = time();

        if ( ! defined($last_time) ) {
            $last_time = $time;
        }

        $delta = $time - $last_time;
        $last_time = $time;

        foreach $peer ( values(%{$this->{_peer_list}}) ) {
            $peer->_handle_pending_events();

            $min = $peer->_update_timers($delta);
            if ( $min < $min_timer ) {
                $min_timer = $min;
            }

            $this->_update_select($peer);
        }

        @ready = IO::Select->select($this->{_read_fh}, $this->{_write_fh}, $this->{_error_fh}, $min_timer);
        if ( @ready ) {

            # dispatch ready to reads
            foreach $ready ( @{$ready[0]} ) {
                if ( $ready == $this->{_listen_socket} ) {
                    $this->_handle_accept();
                }
                else {
                    $peer = $this->{_peer_sock_map}->{$ready};
                    $peer->_handle_socket_read_ready();
                }
            }

            # dispatch ready to writes
            foreach $ready ( @{$ready[1]} ) {
                $peer = $this->{_peer_sock_map}->{$ready};
                $peer->_handle_socket_write_ready();
            }

            # dispatch exception conditions
            foreach $ready ( @{$ready[2]} ) {
                $peer = $this->{_peer_sock_map}->{$ready};
                $peer->_handle_socket_error_condition();
            }
        }
    }

    $this->_cleanup();
}

## Private Methods ##

sub _add_peer_sock
{
    my ($this, $peer, $sock) = @_;

    $this->{_peer_sock}->{$peer} = $sock;
    $this->{_peer_sock_fh}->{$peer} = $sock->fileno();
    $this->{_peer_sock_map}->{$sock} = $peer;
}

sub _remove_peer_sock
{
    my ($this, $peer) = @_;

    delete $this->{_peer_sock_map}->{$this->{_peer_sock}->{$peer}};
    delete $this->{_peer_sock}->{$peer};
    delete $this->{_peer_sock_fh}->{$peer};
}

sub _init_listen_socket
{
    my $this = shift();
    my ($socket, $proto, $rv, $sock_addr);

    eval {
        $socket = new IO::Socket( Domain => AF_INET );
        if ( ! defined($socket) ) {
            die("IO::Socket construction failed");
        }

        $rv = $socket->blocking(FALSE);
        if ( ! defined($rv) ) {
            die("set socket non-blocking failed");
        }

        $proto = getprotobyname('tcp');
        $rv = $socket->socket(PF_INET, SOCK_STREAM, $proto);
        if ( ! defined($rv) ) {
            die("socket() failed");
        }

        $sock_addr = sockaddr_in($this->{_listen_port}, INADDR_ANY);
        $rv = $socket->bind($sock_addr);
        if ( ! defined($rv) ) {
            die("bind() failed");
        }

        $socket->sockopt(SO_REUSEADDR, TRUE);

        $rv = $socket->listen(LISTEN_QUEUE_SIZE);
        if ( ! defined($rv) ) {
            die("listen() failed");
        }

        $this->{_read_fh}->add($socket);
        $this->{_write_fh}->add($socket);
        $this->{_error_fh}->add($socket);
        $this->{_listen_socket} = $socket;
    };
}

sub _cleanup
{
    my $this = shift();
    my $socket;

    if ( defined($this->{_listen_socket}) ) {
        $socket = $this->{_listen_socket};
        $this->{_read_fh}->remove($socket);
        $this->{_write_fh}->remove($socket);
        $this->{_error_fh}->remove($socket);

        $socket->close();
        $this->{_listen_socket} = undef;
    }
}

sub _handle_accept
{
    my $this = shift();
    my ($socket, $peer, $peer_addr);
    my ($port, $addr, $ip_addr);

    ($socket, $peer_addr) = $this->{_listen_socket}->accept();
    ($port, $addr) = sockaddr_in($peer_addr);
    $ip_addr = inet_ntoa($addr);

    if ( ! defined($this->{_peer_addr}->{$ip_addr}) ) {
        $socket->close();
    }
    elsif ( ! $this->{_peer_addr}->{$ip_addr}->_is_listener() ) {
        $socket->close();
    }
    else {
        # reuse the existing Net::BGP4::Peer object if it is a passive session
        if ( $this->{_peer_addr}->{$ip_addr}->_is_passive() ) {
            $peer = $this->{_peer_addr}->{$ip_addr};
        }
        else {
            $peer = $this->{_peer_addr}->{$ip_addr}->_clone();
            $this->add_peer($peer);
        }

        $peer->_set_socket($socket);
    }
}

sub _update_select
{
    my ($this, $peer) = @_;
    my ($peer_socket, $this_socket);

    $peer_socket = $peer->_get_socket();
    $this_socket = $this->{_peer_sock}->{$peer};

    if ( defined($peer_socket) && ! defined($this_socket) ) {
        $this->_add_peer_sock($peer, $peer_socket);
        $this->{_read_fh}->add($peer_socket);
        $this->{_write_fh}->add($peer_socket);
        $this->{_error_fh}->add($peer_socket);
    }
    elsif ( defined($this_socket) && ! defined($peer_socket) ) {
        $this->{_read_fh}->remove($this->{_peer_sock_fh}->{$peer});
        $this->{_write_fh}->remove($this->{_peer_sock_fh}->{$peer});
        $this->{_error_fh}->remove($this->{_peer_sock_fh}->{$peer});
        $this->_remove_peer_sock($peer);
    }
    elsif ( defined($this_socket) && defined($peer_socket) ) {
        if ( $this_socket->connected() && $this->{_write_fh}->exists($this_socket) ) {
            $this->{_write_fh}->remove($this_socket);
        }
    }
}

## POD ##

=pod

=head1 NAME

Net::BGP4::Process - Class encapsulating BGP4 session multiplexing functionality

=head1 SYNOPSIS

    use Net::BGP4::Process;

    $bgp = new Net::BGP4::Process( Port => $port );

    $bgp->add_peer($peer);
    $bgp->remove_peer($peer);
    $bgp->event_loop();

=head1 DESCRIPTION

This module encapsulates the functionality necessary to multiplex multiple
BGP peering sessions. While individual B<Net::BGP4::Peer> objects contain
the state of each peering session, it is the B<Net::BGP4::Process> object
which monitors each peer's transport-layer connection and timers and signals
the peer whenever messages are available for processing or timers expire.
A B<Net::BGP4::Process> object must be instantiated, even if a program only
intends to establish a session with a single peer.

=head1 METHODS

I<new()> - create a new Net::BGP4::Process object

    $bgp = new Net::BGP4::Process( Port => $port );

This is the constructor for Net::BGP4::Process objects. It returns a
reference to the newly created object. The following named parameters may
be passed to the constructor.

=head2 Port

This parameter sets the TCP port the BGP process listens on. It may be
omitted, in which case it defaults to the well-known BGP port TCP/179.
If the program cannot run with root priviliges, it is necessary to set
this parameter to a value greater than or equal to 1024. Note that some
BGP implementations may not allow the specification of an alternate port
and may be unable to establish a connection to the B<Net::BGP4::Process>.

I<add_peer()> - add a new peer to the BGP process

    $bgp->add_peer($peer);

Each B<Net::BGP4::Peer> object, which corresponds to a distinct peering
session, must be registered with the B<Net::BGP4::Process> object via this
method. It is typically called immediately after a new peer object is created
to add the peer to the BGP process. The method accepts a single parameter,
which is a reference to a B<Net::BGP4::Peer> object.

I<remove_peer()> - remove a peer from the BGP process

    $bgp->remove_peer($peer);

This method should be called if a peer should no longer be managed by the
BGP process, for example, if the session is broken or closed and will not
be re-established. The method accepts a single parameter, which is a
reference to a B<Net::BGP4::Peer> object which has previously been registered
with the process object with the I<add_peer()> method.

I<event_loop()> - start the process event loop

    $bgp->event_loop();

This method must called after all peers are instantiated and added to the
BGP process and any other necessary initialization has occured. Once it
is called, it takes over program control flow, and control will
only return to user code when one of the event callback functions is
invoked upon receipt of a BGP protocol message or a user
established timer expires (see the B<Net::BGP4::Peer> manpage for details
on how to establish timers and callback functions). The method takes
no parameters. It will only return when there are no B<Net::BGP4::Peer>
objects remaining under its management, which can only occur if they
are explicitly removed with the I<remove_peer()> method (perhaps called
in one of the callback or timer functions).

=head1 SEE ALSO

B<Net::BGP4>, B<Net::BGP4::Peer>, B<Net::BGP4::Update>,
B<Net::BGP4::Notification>

=head1 AUTHOR

Stephen J. Scheck <code@neurosphere.com>

=cut

## End Package Net::BGP4::Process ##

1;
