package Net::BGP4::Peer;

use strict;
use vars qw(
    $VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS @BGP @GENERIC
    @BGP_EVENT_MESSAGE_MAP @BGP_EVENTS @BGP_FSM @BGP_STATES
);

## Inheritance and Versioning ##

@ISA     = qw( Exporter );
$VERSION = '0.01';

## Module Imports ##

use Exporter;
use IO::Socket;
use Net::BGP4::Notification qw( :errors );
use Net::BGP4::Update;

## General Definitions ##

sub TRUE  { 1 }
sub FALSE { 0 }

## BGP4 Network Constants ##

sub BGP_PORT      { 179 }
sub BGP_VERSION_4 {   4 }

## BGP4 General Constant Definitions ##

sub BGP_MESSAGE_HEADER_LENGTH { 19 }
sub BGP_MAX_MESSAGE_LENGTH    { 4096 }
sub BGP_CONNECT_RETRY_TIME    { 120 }
sub BGP_HOLD_TIME             { 90 }
sub BGP_KEEPALIVE_TIME        { 30 }

## BGP4 Finite State Machine State Enumerations ##

sub BGP_STATE_IDLE         { 1 }
sub BGP_STATE_CONNECT      { 2 }
sub BGP_STATE_ACTIVE       { 3 }
sub BGP_STATE_OPEN_SENT    { 4 }
sub BGP_STATE_OPEN_CONFIRM { 5 }
sub BGP_STATE_ESTABLISHED  { 6 }

## BGP4 State Names ##

@BGP_STATES = qw( Null Idle Connect Active OpenSent OpenConfirm Established );

## BGP4 Event Enumerations ##

sub BGP_EVENT_START                        { 1 }
sub BGP_EVENT_STOP                         { 2 }
sub BGP_EVENT_TRANSPORT_CONN_OPEN          { 3 }
sub BGP_EVENT_TRANSPORT_CONN_CLOSED        { 4 }
sub BGP_EVENT_TRANSPORT_CONN_OPEN_FAILED   { 5 }
sub BGP_EVENT_TRANSPORT_FATAL_ERROR        { 6 }
sub BGP_EVENT_CONNECT_RETRY_TIMER_EXPIRED  { 7 }
sub BGP_EVENT_HOLD_TIMER_EXPIRED           { 8 }
sub BGP_EVENT_KEEPALIVE_TIMER_EXPIRED      { 9 }
sub BGP_EVENT_RECEIVE_OPEN_MESSAGE         { 10 }
sub BGP_EVENT_RECEIVE_KEEP_ALIVE_MESSAGE   { 11 }
sub BGP_EVENT_RECEIVE_UPDATE_MESSAGE       { 12 }
sub BGP_EVENT_RECEIVE_NOTIFICATION_MESSAGE { 13 }

## BGP4 Event Names ##

@BGP_EVENTS = (
    'Null',
    'BGP Start',
    'BGP Stop',
    'BGP Transport connection open',
    'BGP Transport connection closed',
    'BGP Transport connection open failed',
    'BGP Transport fatal error',
    'ConnectRetry timer expired',
    'Hold Timer expired',
    'KeepAlive timer expired',
    'Receive OPEN message',
    'Receive KEEPALIVE message',
    'Receive UPDATE message',
    'Receive NOTIFICATION message'
);

## BGP4 Protocol Message Type Enumerations ##

sub BGP_MESSAGE_OPEN         { 1 }
sub BGP_MESSAGE_UPDATE       { 2 }
sub BGP_MESSAGE_NOTIFICATION { 3 }
sub BGP_MESSAGE_KEEPALIVE    { 4 }

## Event-Message Type Correlation ##

@BGP_EVENT_MESSAGE_MAP = (
    undef,
    BGP_EVENT_RECEIVE_OPEN_MESSAGE,
    BGP_EVENT_RECEIVE_UPDATE_MESSAGE,
    BGP_EVENT_RECEIVE_NOTIFICATION_MESSAGE,
    BGP_EVENT_RECEIVE_KEEP_ALIVE_MESSAGE
);

## BGP4 FSM State Transition Table ##

@BGP_FSM = (
    undef,                                     # Null (zero placeholder)

    [                                          # Idle
        '_close_session',                      # Default transition
        '_handle_bgp_start_event'              # BGP_EVENT_START
    ],
    [                                          # Connect
        '_close_session',                      # Default transition
        '_ignore_start_event',                 # BGP_EVENT_START
        undef,                                 # BGP_EVENT_STOP
        '_handle_bgp_conn_open',               # BGP_EVENT_TRANSPORT_CONN_OPEN
        undef,                                 # BGP_EVENT_TRANSPORT_CONN_CLOSED
        '_handle_connect_retry_restart',       # BGP_EVENT_TRANSPORT_CONN_OPEN_FAILED
        undef,                                 # BGP_EVENT_TRANSPORT_FATAL_ERROR
        '_handle_bgp_start_event'              # BGP_EVENT_CONNECT_RETRY_TIMER_EXPIRED
    ],
    [                                          # Active
        '_close_session',                      # Default transition
        '_ignore_start_event',                 # BGP_EVENT_START
        undef,                                 # BGP_EVENT_STOP
        '_handle_bgp_conn_open',               # BGP_EVENT_TRANSPORT_CONN_OPEN
        undef,                                 # BGP_EVENT_TRANSPORT_CONN_CLOSED
        '_handle_connect_retry_restart',       # BGP_EVENT_TRANSPORT_CONN_OPEN_FAILED
        undef,                                 # BGP_EVENT_TRANSPORT_FATAL_ERROR
        '_handle_bgp_start_event'              # BGP_EVENT_CONNECT_RETRY_TIMER_EXPIRED
    ],
    [                                          # OpenSent
        '_handle_bgp_fsm_error',               # Default transition
        '_ignore_start_event',                 # BGP_EVENT_START
        '_cease',                              # BGP_EVENT_STOP
        undef,                                 # BGP_EVENT_TRANSPORT_CONN_OPEN
        '_handle_open_sent_disconnect',        # BGP_EVENT_TRANSPORT_CONN_CLOSED
        undef,                                 # BGP_EVENT_TRANSPORT_CONN_OPEN_FAILED
        '_close_session',                      # BGP_EVENT_TRANSPORT_FATAL_ERROR
        undef,                                 # BGP_EVENT_CONNECT_RETRY_TIMER_EXPIRED
        '_handle_hold_timer_expired',          # BGP_EVENT_HOLD_TIMER_EXPIRED
        undef,                                 # BGP_EVENT_KEEPALIVE_TIMER_EXPIRED
        '_handle_bgp_open_received'            # BGP_EVENT_RECEIVE_OPEN_MESSAGE
    ],
    [                                          # OpenConfirm
        '_handle_bgp_fsm_error',               # Default transition
        '_ignore_start_event',                 # BGP_EVENT_START
        '_cease',                              # BGP_EVENT_STOP
        undef,                                 # BGP_EVENT_TRANSPORT_CONN_OPEN
        '_close_session',                      # BGP_EVENT_TRANSPORT_CONN_CLOSED
        undef,                                 # BGP_EVENT_TRANSPORT_CONN_OPEN_FAILED
        '_close_session',                      # BGP_EVENT_TRANSPORT_FATAL_ERROR
        undef,                                 # BGP_EVENT_CONNECT_RETRY_TIMER_EXPIRED
        '_handle_hold_timer_expired',          # BGP_EVENT_HOLD_TIMER_EXPIRED
        '_handle_keepalive_expired',           # BGP_EVENT_KEEPALIVE_TIMER_EXPIRED
        undef,                                 # BGP_EVENT_RECEIVE_OPEN_MESSAGE
        '_handle_receive_keepalive_message',   # BGP_EVENT_RECEIVE_KEEP_ALIVE_MESSAGE
        undef,                                 # BGP_EVENT_RECEIVE_UPDATE_MESSAGE
        '_handle_receive_notification_message' # BGP_EVENT_RECEIVE_NOTIFICATION_MESSAGE
    ],
    [                                          # Established
        '_handle_bgp_fsm_error',               # Default transition
        '_ignore_start_event',                 # BGP_EVENT_START
        '_cease',                              # BGP_EVENT_STOP
        undef,                                 # BGP_EVENT_TRANSPORT_CONN_OPEN
        '_close_session',                      # BGP_EVENT_TRANSPORT_CONN_CLOSED
        undef,                                 # BGP_EVENT_TRANSPORT_CONN_OPEN_FAILED
        '_close_session',                      # BGP_EVENT_TRANSPORT_FATAL_ERROR
        undef,                                 # BGP_EVENT_CONNECT_RETRY_TIMER_EXPIRED
        '_handle_hold_timer_expired',          # BGP_EVENT_HOLD_TIMER_EXPIRED
        '_handle_keepalive_expired',           # BGP_EVENT_KEEPALIVE_TIMER_EXPIRED
        undef,                                 # BGP_EVENT_RECEIVE_OPEN_MESSAGE
        '_handle_receive_keepalive_message',   # BGP_EVENT_RECEIVE_KEEP_ALIVE_MESSAGE
        '_handle_receive_update_message',      # BGP_EVENT_RECEIVE_UPDATE_MESSAGE
        '_handle_receive_notification_message' # BGP_EVENT_RECEIVE_NOTIFICATION_MESSAGE
    ]
);

## Socket States ##

sub AWAITING_HEADER_START     { 1 }
sub AWAITING_HEADER_FRAGMENT  { 2 }
sub AWAITING_MESSAGE_FRAGMENT { 3 }

## Export Tag Definitions ##

@BGP         = qw( BGP_PORT BGP_VERSION_4 );
@GENERIC     = qw( TRUE FALSE dump_hex );
@EXPORT      = ();
@EXPORT_OK   = ( @BGP, @GENERIC );
%EXPORT_TAGS = (
    bgp      => [ @BGP ],
    generic  => [ @GENERIC ],
    ALL      => [ @EXPORT, @EXPORT_OK ]
);

## Generic Subroutines ##

# This subroutine was snicked from David Town's excellent Net::SNMP
# module and renamed as dump_hex(). Removed class dependence and made
# into standalone subroutine.

sub dump_hex
{
   my $data = shift();
   my ($length, $offset, $line, $hex) = (0, 0, '', '');

   $length = length($data);

   while ($length > 0) {
      if ($length >= 16) {
         $line = substr($data, $offset, 16);
      } else {
         $line = substr($data, $offset, $length);
      }
      $hex  = unpack('H*', $line);
      $hex .= ' ' x (32 - length($hex));
      $hex  = sprintf("%s %s %s %s  " x 4, unpack('a2' x 16, $hex));
      $line =~ s/[\x00-\x1f\x7f-\xff]/./g;
      printf STDERR ("[%03d]  %s %s\n", $offset, uc($hex), $line);
      $offset += 16;
      $length -= 16;
   }
   print STDERR ("\n");

   return ( $data );
}

## Public Methods ##

sub new
{
    my $class = shift();
    my ($arg, $value);

    my $this = {
        _bgp_version           => BGP_VERSION_4,
        _local_id              => undef,
        _peer_id               => undef,
        _peer_port             => BGP_PORT,
        _local_as              => 0,
        _peer_as               => 0,
        _hold_time             => BGP_HOLD_TIME,
        _hold_timer            => undef,
        _keep_alive_time       => BGP_KEEPALIVE_TIME,
        _keep_alive_timer      => undef,
        _fsm_state             => BGP_STATE_IDLE,
        _user_timers           => [],
        _event_queue           => [],
        _message_queue         => [],
        _peer_socket           => undef,
        _listen                => TRUE,
        _passive               => FALSE,
        _sibling_peer          => undef,
        _connect_retry_time    => BGP_CONNECT_RETRY_TIME,
        _connect_retry_timer   => undef,
        _last_timer_update     => undef,
        _in_msg_buffer         => '',
        _in_msg_buf_state      => AWAITING_HEADER_START,
        _in_msg_buf_bytes_exp  => 0,
        _in_msg_buf_type       => 0,
        _out_msg_buffer        => '',
        _open_callback         => undef,
        _keepalive_callback    => undef,
        _update_callback       => undef,
        _notification_callback => undef,
        _error_callback        => undef
    };

    bless($this, $class);

    while ( defined($arg = shift()) ) {
        $value = shift();

        if ( $arg =~ /start/i ) {
            $this->start();
        }
        elsif ( $arg =~ /thisid/i ) {
            $this->{_local_id} = $value;
        }
        elsif ( $arg =~ /thisas/i ) {
            $this->{_local_as} = $value;
        }
        elsif ( $arg =~ /peerid/i ) {
            $this->{_peer_id} = $value;
        }
        elsif ( $arg =~ /peeras/i ) {
            $this->{_peer_as} = $value;
        }
        elsif ( $arg =~ /peerport/i ) {
            $this->{_peer_port} = $value;
        }
        elsif ( $arg =~ /holdtime/i ) {
            $this->{_hold_time} = $value;
        }
        elsif ( $arg =~ /connectretrytime/i ) {
            $this->{_connect_retry_time} = $value;
        }
        elsif ( $arg =~ /keepalivetime/i ) {
            $this->{_keep_alive_time} = $value;
        }
        elsif ( $arg =~ /listen/i ) {
            $this->{_listen} = $value;
        }
        elsif ( $arg =~ /passive/i ) {
            $this->{_passive} = $value;
        }
        elsif ( $arg =~ /opencallback/i ) {
            $this->{_open_callback} = $value;
        }
        elsif ( $arg =~ /keepalivecallback/i ) {
            $this->{_keepalive_callback} = $value;
        }
        elsif ( $arg =~ /updatecallback/i ) {
            $this->{_update_callback} = $value;
        }
        elsif ( $arg =~ /notificationcallback/i ) {
            $this->{_notification_callback} = $value;
        }
        elsif ( $arg =~ /errorcallback/i ) {
            $this->{_error_callback} = $value;
        }
        else {
            die("unrecognized argument $arg\n");
        }
    }

    return ( $this );
}

sub start
{
    my $this = shift();
    $this->_enqueue_event(BGP_EVENT_START);
}

sub stop
{
    my $this = shift();
    $this->{_fsm_state} = $this->_cease();
}

sub update
{
    my ($this, $update) = @_;
    my ($buffer, $result);

    $result = FALSE;
    if ( $this->{_fsm_state} == BGP_STATE_ESTABLISHED ) {
        $buffer = $this->_encode_bgp_update_message($update->_encode_message());
        $this->_send_msg($buffer);
        $result = TRUE;
    }

    return ( $result );
}

sub this_id
{
    my $this = shift();
    return ( $this->{_local_id} );
}

sub this_as
{
    my $this = shift();
    return ( $this->{_local_as} );
}

sub peer_id
{
    my $this = shift();
    return ( $this->{_peer_id} );
}

sub peer_as
{
    my $this = shift();
    return ( $this->{_peer_as} );
}

sub version
{
    my $this = shift();
    return ( $this->{_bgp_version} );
}

sub set_open_callback
{
    my ($this, $callback) = @_;
    $this->{_open_callback} = $callback;
}

sub set_keepalive_callback
{
    my ($this, $callback) = @_;
    $this->{_keepalive_callback} = $callback;
}

sub set_update_callback
{
    my ($this, $callback) = @_;
    $this->{_update_callback} = $callback;
}

sub set_notification_callback
{
    my ($this, $callback) = @_;
    $this->{_notification_callback} = $callback;
}

sub set_error_callback
{
    my ($this, $callback) = @_;
    $this->{_error_callback} = $callback;
}

sub add_timer
{
    my ($this, $callback, $timeout) = @_;
    my $timer;

    $timer = {
        _timer    => $timeout,
        _timeout  => $timeout,
        _callback => $callback,
    };

    push(@{$this->{_user_timers}}, $timer);
}

sub remove_timer
{
    my ($this, $callback) = @_;
    my $timer;

    foreach $timer ( @{$this->{_user_timers}} ) {
        if ( $timer->{_callback} == $callback ) {
            $timer->{_timer} = undef;
            $timer->{_callback} = undef;
        }
    }
}

## Overridable Methods ##

sub open_callback
{
    my $this = shift();

    if ( defined($this->{_open_callback}) ) {
        &{ $this->{_open_callback} }($this);
    }
}

sub keepalive_callback
{
    my $this = shift();

    if ( defined($this->{_keepalive_callback}) ) {
        &{ $this->{_keepalive_callback} }($this);
    }
}

sub update_callback
{
    my ($this, $update) = @_;

    if ( defined($this->{_update_callback}) ) {
        &{ $this->{_update_callback} }($this, $update);
    }
}

sub notification_callback
{
    my ($this, $error) = @_;

    if ( defined($this->{_notification_callback}) ) {
        &{ $this->{_notification_callback} }($this, $error);
    }
}

sub error_callback
{
    my ($this, $error) = @_;

    if ( defined($this->{_error_callback}) ) {
        &{ $this->{_error_callback} }($this, $error);
    }
}

## Private Methods ##

sub _clone
{
    my $this = shift();
    my ($clone, $key);

    $clone = {};
    foreach $key ( keys(%{ $this }) ) {
        $clone->{$key} = $this->{$key};
    }

    # override some of the inherited properties

    $clone->{_hold_timer}           = undef;
    $clone->{_keep_alive_timer}     = undef;
    $clone->{_fsm_state}            = BGP_STATE_IDLE;
    $clone->{_event_queue}          = [];
    $clone->{_message_queue}        = [];
    $clone->{_peer_socket}          = undef;
    $clone->{_listen}               = FALSE;
    $clone->{_passive}              = TRUE;
    $clone->{_sibling_peer}         = $this;
    $clone->{_connect_retry_timer}  = undef;
    $clone->{_last_timer_update}    = undef;
    $clone->{_in_msg_buffer}        = '';
    $clone->{_in_msg_buf_state}     = AWAITING_HEADER_START;
    $clone->{_in_msg_buf_bytes_exp} = 0;
    $clone->{_in_msg_buf_type}      = 0;
    $clone->{_out_msg_buffer}       = '';

    bless($clone, ref($this));

    # set _sibling_peer to the cloned object
    $this->{_sibling_peer} = $clone;

    if ( $this->{_fsm_state} != BGP_STATE_IDLE ) {
        $clone->start();
    }

    return ( $clone );
}

sub _error
{
    my $this = shift();
    my $error;

    $error = new Net::BGP4::Notification(
        ErrorCode    => shift(),
        ErrorSubCode => shift(),
        ErrorData    => shift()
    );

    return ( $error );
}

sub _is_listener
{
    my $this = shift();
    return ( $this->{_listen} );
}

sub _is_passive
{
    my $this = shift();
    return ( $this->{_passive} );
}

sub _get_socket
{
    my $this = shift();
    return ( $this->{_peer_socket} );
}

sub _set_socket
{
    my ($this, $socket) = @_;
    $this->{_peer_socket} = $socket;
}

sub _enqueue_event
{
    my $this = shift();
    push(@{ $this->{_event_queue} }, shift());
}

sub _dequeue_event
{
    my $this = shift();
    return ( shift(@{ $this->{_event_queue} }) );
}

sub _enqueue_message
{
    my $this = shift();
    push(@{ $this->{_message_queue} }, shift());
}

sub _dequeue_message
{
    my $this = shift();
    return ( shift(@{ $this->{_message_queue} }) );
}

sub _handle_event
{
    my ($this, $event) = @_;
    my ($state, $action, $next_state, $next_state_name, $event_name);

    $action = $BGP_FSM[$this->{_fsm_state}]->[$event];
    if ( ! defined($action) ) {
        $action = $BGP_FSM[$this->{_fsm_state}]->[0];
    }

    # do action associated with transition
    if ( defined($action) ) {
        $next_state = $this->$action;
    }

    $state = $BGP_STATES[$this->{_fsm_state}];
    $event_name = $BGP_EVENTS[$event];
    $next_state_name = $BGP_STATES[$next_state];

    # transition to next state
    $this->{_fsm_state} = $next_state;
}

sub _handle_pending_events
{
    my $this = shift();
    my $event;

    # flush the outbound message buffer
    if ( length($this->{_out_msg_buffer}) ) {
        $this->_send_msg();
    }

    while ( defined($event = $this->_dequeue_event()) ) {
        $this->_handle_event($event);
    }
}

sub _update_timers
{
    my ($this, $delta) = @_;
    my ($timer, $min, $min_time);
    my %timers = (
        _connect_retry_timer => BGP_EVENT_CONNECT_RETRY_TIMER_EXPIRED,
        _hold_timer          => BGP_EVENT_HOLD_TIMER_EXPIRED,
        _keep_alive_timer    => BGP_EVENT_KEEPALIVE_TIMER_EXPIRED
    );

    $min_time = 3600;
    if ( length($this->{_out_msg_buffer}) ) {
        $min_time = 0;
    }

    # Update BGP4 timers
    foreach $timer ( keys(%timers) ) {
        if ( defined($this->{$timer}) ) {
            $this->{$timer} -= $delta;

            if ( $this->{$timer} <= 0 ) {
                $this->{$timer} = 0;
                $this->_enqueue_event($timers{$timer});
            }

            if ( $this->{$timer} < $min_time ) {
                $min_time = $this->{$timer};
            }
        }
    }

    # Update user defined timers
    foreach $timer ( @{$this->{_user_timers}} ) {
        if ( defined($timer->{_timer}) ) {
            $timer->{_timer} -= $delta;

            $min = ($timer->{_timer} < 0) ? 0 : $timer->{_timer};
            if ( $timer->{_timer} <= 0 ) {
                $timer->{_timer} = $timer->{_timeout};
                &{ $timer->{_callback} }($this);
            }

            if ( $min < $min_time ) {
                $min_time = $min;
            }
        }
    }

    return ( $min_time );
}

sub _send_msg
{
    my ($this, $msg) = @_;
    my ($buffer, $sent);

    $buffer = $this->{_out_msg_buffer} . $msg;
    $sent = $this->{_peer_socket}->syswrite($buffer);

    if ( ! defined($sent) ) {
        die("fatal error on socket write!\n");
    }

    $this->{_out_msg_buffer} = substr($buffer, $sent);
}

sub _handle_socket_read_ready
{
    my $this = shift();
    my ($socket, $buffer, $num_read, $conn_closed);

    $conn_closed = FALSE;
    $socket = $this->{_peer_socket};
    $buffer = $this->{_in_msg_buffer};

    if ( $this->{_in_msg_buf_state} == AWAITING_HEADER_START ) {
        $num_read = $socket->sysread($buffer, BGP_MESSAGE_HEADER_LENGTH, length($buffer));
        if ( $num_read == 0 ) {
            $conn_closed = TRUE;
        }
        elsif ( $num_read != BGP_MESSAGE_HEADER_LENGTH ) {
            $this->{_in_msg_buf_state} = AWAITING_HEADER_FRAGMENT;
            $this->{_in_msg_buf_bytes_exp} = BGP_MESSAGE_HEADER_LENGTH - $num_read;
            $this->{_in_msg_buffer} = $buffer;
        }
        else {
            $this->_decode_bgp_message_header($buffer);
            $this->{_in_msg_buffer} = '';
        }
    }
    elsif ( $this->{_in_msg_buf_state} == AWAITING_HEADER_FRAGMENT ) {
        $num_read = $socket->sysread($buffer, $this->{_in_msg_buf_bytes_exp}, length($buffer));
        if ( $num_read == 0 ) {
            $conn_closed = TRUE;
        }
        elsif ( $num_read == $this->{_in_msg_buf_bytes_exp} ) {
            $this->_decode_bgp_message_header($buffer);
            $this->{_in_msg_buffer} = '';
        }
        else {
            $this->{_in_msg_buf_bytes_exp} -= $num_read;
            $this->{_in_msg_buffer} = $buffer;
        }
    }
    elsif ( $this->{_in_msg_buf_state} == AWAITING_MESSAGE_FRAGMENT ) {
        $num_read = $socket->sysread($buffer, $this->{_in_msg_buf_bytes_exp}, length($buffer));
        if ( ($num_read == 0) && ($this->{_in_msg_buf_bytes_exp} != 0) ) {
            $conn_closed = TRUE;
        }
        elsif ( $num_read == $this->{_in_msg_buf_bytes_exp} ) {
            $this->_enqueue_message($buffer);
            $this->_enqueue_event($BGP_EVENT_MESSAGE_MAP[$this->{_in_msg_buf_type}]);
            $this->{_in_msg_buffer} = '';
            $this->{_in_msg_buf_state} = AWAITING_HEADER_START;
        }
        else {
            $this->{_in_msg_buf_bytes_exp} -= $num_read;
            $this->{_in_msg_buffer} = $buffer;
        }
    }
    else {
        die("unknown socket state!\n");
    }

    if ( $conn_closed ) {
        $this->_enqueue_event(BGP_EVENT_TRANSPORT_CONN_CLOSED);
    }
}

sub _handle_socket_write_ready
{
    my $this = shift();
    $this->_enqueue_event(BGP_EVENT_TRANSPORT_CONN_OPEN);
}

sub _handle_socket_error_condition
{
    my $this = shift();
    print STDERR "_handle_socket_error_condition()\n";
    print STDERR $this->{_peer_socket}->error(), "\n";
}

sub _close_session
{
    my $this = shift();
    my $socket = $this->{_peer_socket};

    if ( defined($socket) ) {
        $socket->close();
    }

    $this->{_peer_socket} = $socket = undef;
    $this->{_in_msg_buffer} = '';
    $this->{_in_msg_buf_state} = AWAITING_HEADER_START;
    $this->{_hold_timer} = undef;
    $this->{_keep_alive_timer} = undef;
    $this->{_connect_retry_timer} = undef;

    return ( BGP_STATE_IDLE );
}

sub _kill_session
{
    my ($this, $error) = @_;
    my $buffer;

    $buffer = $this->_encode_bgp_notification_message(
        $error->error_code(),
        $error->error_subcode(),
        $error->error_data()
    );

    $this->_send_msg($buffer);
    $this->_close_session();

    # invoke user callback function
    $this->error_callback($error);
}

sub _ignore_start_event
{
    my $this = shift();
    return ( $this->{_fsm_state} );
}

sub _handle_receive_keepalive_message
{
    my $this = shift();

    # restart Hold Timer
    if ( $this->{_hold_time} != 0 ) {
        $this->{_hold_timer} = $this->{_hold_time};
    }

    # invoke user callback function
    $this->keepalive_callback();

    return ( BGP_STATE_ESTABLISHED );
}

sub _handle_receive_update_message
{
    my $this = shift();
    my ($buffer, $update);

    # restart Hold Timer
    if ( $this->{_hold_time} != 0 ) {
        $this->{_hold_timer} = $this->{_hold_time};
    }

    $buffer = $this->_dequeue_message();
    $update = Net::BGP4::Update->_new_from_msg($buffer);

    if ( ref($update) eq 'Net::BGP4::Notification' ) {
        $this->_kill_session($update);
        return ( BGP_STATE_IDLE );
    }

    # invoke user callback function
    $this->update_callback($update);

    return ( BGP_STATE_ESTABLISHED );
}

sub _handle_receive_notification_message
{
    my $this = shift();
    my $error;

    $error = $this->_decode_bgp_notification_message($this->_dequeue_message());
    $this->_close_session();

    # invoke user callback function
    $this->notification_callback($error);

    return ( BGP_STATE_IDLE );
}

sub _handle_keepalive_expired
{
    my $this = shift();
    my $buffer;

    # send KEEPALIVE message to peer
    $buffer = $this->_encode_bgp_keepalive_message();
    $this->_send_msg($buffer);

    # restart KeepAlive timer
    $this->{_keep_alive_timer} = $this->{_keep_alive_time};

    return ( $this->{_fsm_state} );
}

sub _handle_hold_timer_expired
{
    my $this = shift();
    my $error;

    $error = $this->_error(BGP_ERROR_CODE_HOLD_TIMER_EXPIRED, BGP_ERROR_SUBCODE_NULL);
    $this->_kill_session($error);
    return ( BGP_STATE_IDLE );
}

sub _handle_bgp_fsm_error
{
    my $this = shift();
    my $error;

    $error = $this->_error(BGP_ERROR_CODE_FINITE_STATE_MACHINE, BGP_ERROR_SUBCODE_NULL);
    $this->_kill_session($error);
    return ( BGP_STATE_IDLE );
}

sub _handle_bgp_conn_open
{
    my $this = shift();
    my $buffer;

    # clear ConnectRetry timer
    $this->{_connect_retry_timer} = undef;

    # send OPEN message to peer
    $buffer = $this->_encode_bgp_open_message();
    $this->_send_msg($buffer);

    return ( BGP_STATE_OPEN_SENT );
}

sub _handle_bgp_open_received
{
    my $this = shift();
    my ($buffer, $this_id, $peer_id);

    if ( ! $this->_decode_bgp_open_message($this->_dequeue_message()) ) {
        ; # do failure stuff
        return ( BGP_STATE_IDLE );
    }

    # check for connection collision
    if ( defined($this->{_sibling_peer}) ) {
        if ( ($this->{_sibling_peer}->{_fsm_state} == BGP_STATE_OPEN_SENT) ||
             ($this->{_sibling_peer}->{_fsm_state} == BGP_STATE_OPEN_CONFIRM) ) {

            $this_id = unpack('N', inet_aton($this->{_local_id}));
            $peer_id = unpack('N', inet_aton($this->{_peer_id}));

            if ( $this_id < $peer_id ) {
                $this->stop();
                return ( BGP_STATE_IDLE );
            }
            else {
                $this->{_sibling_peer}->stop();
                return ( BGP_STATE_OPEN_CONFIRM );
            }
        }
        elsif ( ($this->{_sibling_peer}->{_fsm_state} == BGP_STATE_ESTABLISHED) ) {
            $this->stop();
            return ( BGP_STATE_IDLE );
        }
    }

    # clear the message buffer after decoding and validation
    $this->{_message} = undef;

    # send KEEPALIVE message to peer
    $buffer = $this->_encode_bgp_keepalive_message();
    $this->_send_msg($buffer);

    # set Hold Time and KeepAlive timers
    if ( $this->{_hold_time} != 0 ) {
        $this->{_hold_timer} = $this->{_hold_time};
        $this->{_keep_alive_timer} = $this->{_keep_alive_time};
    }

    # invoke user callback function
    $this->open_callback();

    # transition to state OpenConfirm
    return ( BGP_STATE_OPEN_CONFIRM );
}

sub _handle_open_sent_disconnect
{
    my $this = shift();

    $this->_close_session();
    return ( $this->_handle_connect_retry_restart() );
}

sub _handle_connect_retry_restart
{
    my $this = shift();

    # restart ConnectRetry timer
    $this->{_connect_retry_timer} = $this->{_connect_retry_time};

    return ( BGP_STATE_ACTIVE );
}

sub _handle_bgp_start_event
{
    my $this = shift();
    my ($socket, $proto, $remote_addr, $rv);

    # initialize ConnectRetry timer
    if ( ! $this->{_passive} ) {
        $this->{_connect_retry_timer} = $this->{_connect_retry_time};
    }

    # initiate the TCP transport connection
    if ( ! $this->{_passive} ) {
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

            $remote_addr = sockaddr_in($this->{_peer_port}, inet_aton($this->{_peer_id}));
            $rv = $socket->connect($remote_addr);
            if ( ! defined($rv) ) {
                die("connect() failed");
            }
        };

        # check for exception in transport initiation
        if ( $@ ) {
            if ( defined($socket) ) {
                $socket->close();
            }

            $this->{_peer_socket} = $socket = undef;
            $this->_enqueue_event(BGP_EVENT_TRANSPORT_CONN_OPEN_FAILED);
        }

        $this->{_peer_socket} = $socket;
    }

    return ( BGP_STATE_CONNECT );
}

sub _min
{
    my ($a, $b) = @_;
    return ( ($a < $b) ? $a : $b );
}

sub _cease
{
    my $this = shift();
    my $error;

    $error = $this->_error(BGP_ERROR_CODE_CEASE, BGP_ERROR_SUBCODE_NULL);
    $this->_kill_session($error);

    return ( BGP_STATE_IDLE );
}

sub _encode_bgp_message
{
    my ($this, $type, $payload) = @_;
    my ($buffer, $length);

    $length = BGP_MESSAGE_HEADER_LENGTH;
    if ( defined($payload) ) {
       $length += length($payload);
       $buffer = $payload;
    }

    # encode the type field
    $buffer = pack('C', $type) . $buffer;

    # encode the length field
    $buffer = pack('n', $length) . $buffer;

    # encode the marker field
    if ( defined($this->{_auth_data}) ) {
        $buffer = $this->{_auth_data} . $buffer;
    }
    else {
        $buffer = (pack('C', 0xFF) x 16) . $buffer;
    }

    return ( $buffer );
}

sub _decode_bgp_message_header
{
    my ($this, $header) = @_;
    my ($marker, $length, $type);
    my $error;

    # validate the BGP message header length
    if ( length($header) != BGP_MESSAGE_HEADER_LENGTH ) {
        $error = $this->_error(
            BGP_ERROR_CODE_MESSAGE_HEADER,
            BGP_ERROR_SUBCODE_BAD_MSG_LENGTH,
            pack('n', length($header))
        );

        $this->_kill_session($error);
    }

    # decode and validate the message header Marker field
    $marker = substr($header, 0, 16);
    if ( $marker ne (pack('C', 0xFF) x 16) ) {
        $error = $this->_error(BGP_ERROR_CODE_MESSAGE_HEADER, BGP_ERROR_SUBCODE_CONN_NOT_SYNC);
        $this->_kill_session($error);
    }

    # decode and validate the message header Length field
    $length = unpack('n', substr($header, 16, 2));
    if ( ($length < BGP_MESSAGE_HEADER_LENGTH) || ($length > BGP_MAX_MESSAGE_LENGTH) ) {
        $error = $this->_error(
            BGP_ERROR_CODE_MESSAGE_HEADER,
            BGP_ERROR_SUBCODE_BAD_MSG_LENGTH,
            pack('n', $length)
        );

        $this->_kill_session($error);
    }

    # decode and validate the message header Type field
    $type = unpack('C', substr($header, 18, 1));
    if ( ($type < BGP_MESSAGE_OPEN) || ($type > BGP_MESSAGE_KEEPALIVE) ) {
        $error = $this->_error(
            BGP_ERROR_CODE_MESSAGE_HEADER,
            BGP_ERROR_SUBCODE_BAD_MSG_TYPE,
            pack('C', $type)
        );

        $this->_kill_session($error);
    }

    if ( $type == BGP_MESSAGE_KEEPALIVE ) {
        $this->{_in_msg_buffer} = '';
        $this->{_in_msg_buf_state} = AWAITING_HEADER_START;
        $this->{_in_msg_buf_bytes_exp} = 0;
        $this->{_in_msg_buf_type} = 0;
        $this->_enqueue_event(BGP_EVENT_RECEIVE_KEEP_ALIVE_MESSAGE);
    }
    else {
        $this->{_in_msg_buf_state} = AWAITING_MESSAGE_FRAGMENT;
        $this->{_in_msg_buf_bytes_exp} = $length - BGP_MESSAGE_HEADER_LENGTH;
        $this->{_in_msg_buf_type} = $type;
    }

    # indicate decoding and validation success
    return ( TRUE );
}

sub _encode_bgp_open_message
{
    my $this = shift();
    my ($buffer, $length);

    # encode optional parameters and length (not currently supported)
    $buffer = pack('C', 0x00);

    # encode BGP Identifier field
    $buffer = inet_aton($this->{_local_id}) . $buffer;

    # encode Hold Time
    $buffer = pack('n', $this->{_hold_time}) . $buffer;

    # encode local Autonomous System number
    $buffer = pack('n', $this->{_local_as}) . $buffer;

    # encode BGP version
    $buffer = pack('C', $this->{_bgp_version}) . $buffer;

    return ( $this->_encode_bgp_message(BGP_MESSAGE_OPEN, $buffer) );
}

sub _decode_bgp_open_message
{
    my ($this, $buffer) = @_;
    my ($version, $as, $hold_time, $bgp_id);
    my $error;

    # decode and validate BGP version
    $version = unpack('C', substr($buffer, 0, 1));
    if ( $version != BGP_VERSION_4 ) {
        $error = $this->_error(
            BGP_ERROR_CODE_OPEN_MESSAGE,
            BGP_ERROR_SUBCODE_BAD_VERSION_NUM,
            pack('n', BGP_VERSION_4)
        );

        $this->_kill_session($error);
    }

    # decode and validate remote Autonomous System number
    $as = unpack('n', substr($buffer, 1, 2));
    if ( $as != $this->{_peer_as} ) {
        $error = $this->_error(BGP_ERROR_CODE_OPEN_MESSAGE, BGP_ERROR_SUBCODE_BAD_PEER_AS);
        $this->_kill_session($error);
    }

    # decode and validate received Hold Time
    $hold_time = _min(unpack('n', substr($buffer, 3, 2)), $this->{_hold_time});
    if ( ($hold_time < 3) && ($hold_time != 0) ) {
        $error = $this->_error(BGP_ERROR_CODE_OPEN_MESSAGE, BGP_ERROR_SUBCODE_BAD_HOLD_TIME);
        $this->_kill_session($error);
    }

    # decode and validate received BGP Identifier
    $bgp_id = inet_ntoa(substr($buffer, 5, 4));
    if ( $bgp_id ne $this->{_peer_id} ) {
        $error = $this->_error(BGP_ERROR_CODE_OPEN_MESSAGE, BGP_ERROR_SUBCODE_BAD_BGP_ID);
        $this->_kill_session($error);
    }

    # Optional Parameters are not supported in this version of Net::BGP4 so
    # they are completely ignored.

    # set Hold Time to negotiated value
    $this->{_hold_time} = $hold_time;

    # indicate decoding and validation success
    return ( TRUE );
}

sub _decode_bgp_notification_message
{
    my ($this, $buffer) = @_;
    my ($error, $error_code, $error_subcode, $data);

    # decode and validate Error code
    $error_code = unpack('C', substr($buffer, 0, 1));
    if ( ($error_code < 1) || ($error_code > 6) ) {
        die("_decode_bgp_notification_message(): invalid error code = $error_code\n");
    }

    # decode and validate Error subcode
    $error_subcode = unpack('C', substr($buffer, 1, 1));
    if ( ($error_subcode < 0) || ($error_subcode > 11) ) {
        die("_decode_bgp_notification_message(): invalid error subcode = $error_subcode\n");
    }

    # decode Data field
    $data = substr($buffer, 2, length($buffer) - 2);

    $error = $this->_error($error_code, $error_subcode, $data);
    return ( $error );
}

sub _encode_bgp_keepalive_message
{
    my $this = shift();
    return ( $this->_encode_bgp_message(BGP_MESSAGE_KEEPALIVE) );
}

sub _encode_bgp_update_message
{
    my ($this, $buffer) = @_;
    return ( $this->_encode_bgp_message(BGP_MESSAGE_UPDATE, $buffer) );
}

sub _encode_bgp_notification_message
{
    my ($this, $error_code, $error_subcode, $data) = @_;
    my $buffer;

    # encode the Data field
    $buffer = $data;

    # encode the Error Subcode field
    $buffer = pack('C', $error_subcode) . $buffer;

    # encode the Error Code field
    $buffer = pack('C', $error_code) . $buffer;

    return ( $this->_encode_bgp_message(BGP_MESSAGE_NOTIFICATION, $buffer) );
}

## POD ##

=pod

=head1 NAME

Net::BGP4::Peer - Class encapsulating BGP4 peering session state and functionality

=head1 SYNOPSIS

    use Net::BGP4::Peer;

    $peer = new Net::BGP4::Peer(
        Start                => 1,
        ThisID               => '10.0.0.1',
        ThisAS               => 64512,
        PeerID               => '10.0.0.2',
        PeerAS               => 64513,
        PeerPort             => 1179,
        ConnectRetryTime     => 300,
        HoldTime             => 60,
        KeepAliveTime        => 20,
        Listen               => 0,
        Passive              => 0,
        OpenCallback         => \&my_open_callback,
        KeepaliveCallback    => \&my_keepalive_callback,
        UpdateCallback       => \&my_update_callback,
        NotificationCallback => \&my_notification_callback,
        ErrorCallback        => \&my_error_callback
    );

    $peer->start();
    $peer->stop();

    use Net::BGP4::Update;
    $update = new Net::BGP4::Update();
    $peer->update($update);

    $this_id = $peer->this_id();
    $this_as = $peer->this_as();
    $peer_id = $peer->peer_id();
    $peer_as = $peer->peer_as();
    $version = $peer->version();

    $peer->set_open_callback(\&my_open_callback);
    $peer->set_keepalive_callback(\&my_keepalive_callback);
    $peer->set_update_callback(\&my_update_callback);
    $peer->set_notification_callback(\&my_notification_callback);
    $peer->set_error_callback(\&my_error_callback);

    $peer->add_timer(\&my_minute_timer, 60);
    $peer->remove_timer(\&my_minute_timer);

=head1 DESCRIPTION

This module encapsulates the state and functionality associated with a BGP
peering session. Each instance of a B<Net::BGP4::Peer> object corresponds
to a peering session with a distinct peer and presents a programming
interface to manipulate the peering session state and exchange of routing
information. Through the methods provided by the B<Net::BGP4::Peer> module,
a program can start or stop peering sessions, send BGP routing UPDATE
messages, and register callback functions which are invoked whenever the
peer receives BGP messages from its peer.

=head1 METHODS

I<new()> - create a new Net::BGP4::Peer object

This is the constructor for Net::BGP4::Peer objects. It returns a
reference to the newly created object. The following named parameters may
be passed to the constructor. Once the object is created, only the
callback function references can later be changed.

=head2 Start

Setting this parameter to a true value causes the peer to initiate a
session with its peer immediately after it is registered with the
B<Net::BGP4::Process> object's I<add_peer()> method. If omitted or
set to a false value, the peer will remain in the Idle state until
the I<start()> method is called explicitly by the program. When in
the Idle state the peer will refuse connections and will not initiate
connection attempts.

=head2 ThisID

This parameter sets the BGP ID (IP address) of the B<Net::BGP4::Peer>
object. It takes a string in IP dotted decimal notation.

=head2 ThisAS

This parameter sets the BGP Autonomous System number of the B<Net::BGP4::Peer>
object. It takes an integer value in the range of a 16-bit unsigned integer.

=head2 PeerID

This parameter sets the BGP ID (IP address) of the object's peer. It takes
a string in IP dotted decimal notation.

=head2 PeerAS

This parameter sets the BGP Autonomous System number of the object's peer.
It takes an integer value in the range of a 16-bit unsigned integer.

=head2 PeerPort

This parameter sets the TCP port number on the peer to which to connect. It
must be in the range of a valid TCP port number.

=head2 ConnectRetryTime

This parameter sets the BGP ConnectRetry timer duration, the value of which
is given in seconds.

=head2 HoldTime

This parameter sets the BGP Hold Time duration, the value of which
is given in seconds.

=head2 KeepAliveTime

This parameter sets the BGP KeepAlive timer duration, the value of which
is given in seconds.

=head2 Listen

This parameter specifies whether the B<Net::BGP4::Peer> will listen for
and accept connections from its peer. If set to a false value, the peer
will only initiate connections and will not accept connection attempts
from the peer (unless the B<Passive> parameter is set to a true value).
Note that this behavior is not specified by RFC 1771 and should be
considered non-standard. However, it is useful under certain circumstances
and should not present problems as long as one side of the connection is
configured to listen.

=head2 Passive

This parameter specifies whether the B<Net::BGP4::Peer> will attempt to
initiate connections to its peer. If set to a true value, the peer will
only listen for connections and will not initate connections to its peer
(unless the B<Listen> parameter is set to false value). Note that this
behavior is not specified by RFC 1771 and should be considered non-standard.
However, it is useful under certain circumstances and should not present
problems as long as one side of the connection is configured to initiate
connections.

=head2 OpenCallback

This parameter sets the callback function which is invoked when the
peer receives an OPEN message. It takes a subroutine reference. See
L<"CALLBACK FUNCTIONS"> later in this manual for further details of
the conventions of callback invocation.

=head2 KeepaliveCallback

This parameter sets the callback function which is invoked when the
peer receives a KEEPALIVE message. It takes a subroutine reference.
See L<"CALLBACK FUNCTIONS"> later in this manual for further details
of the conventions of callback invocation.

=head2 UpdateCallback

This parameter sets the callback function which is invoked when the
peer receives an UPDATE message. It takes a subroutine reference. See
L<"CALLBACK FUNCTIONS"> later in this manual for further details of
the conventions of callback invocation.

=head2 NotificationCallback

This parameter sets the callback function which is invoked when the
peer receives a NOTIFICATION message. It takes a subroutine reference.
See L<"CALLBACK FUNCTIONS"> later in this manual for further details
of the conventions of callback invocation.

=head2 ErrorCallback

This parameter sets the callback function which is invoked when the
peer encounters an error and must send a NOTIFICATION message to its
peer. It takes a subroutine reference. See L<"CALLBACK FUNCTIONS">
later in this manual for further details of the conventions of callback
invocation.

I<start()> - start the BGP peering session with the peer

    $peer->start();

This method initiates the BGP peering session with the peer by
internally emitting the BGP Start event, which causes the peer
to initiate a transport-layer connection to its peer (unless
the B<Passive> parameter was set to a true value in the
constructor) and listen for a connection from the peer (unless
the B<Listen> parameter is set to a false value).

I<stop()> - cease the BGP peering session with the peer

    $peer->stop();

This method immediately ceases the peering session with the
peer by sending it a NOTIFICATION message with Error Code
Cease, closing the transport-layer connection, and entering
the Idle state.

I<update()> - send a BGP UPDATE message to the peer

    $peer->update($update);

This method sends the peer an UPDATE message. It takes a reference
to a B<Net::BGP4::Update> object. See the B<Net::BGP4::Update>
manual page for details on setting UPDATE attributes.

I<this_id()>

I<this_as()>

I<peer_id()>

I<peer_as()>

I<version()>

These are accessor methods for the corresponding constructor named parameters.
They retrieve the values set when the object was created, but the values cannot
be changed after object construction. Hence, they take no arguments.

I<set_open_callback()>

I<set_keepalive_callback()>

I<set_update_callback()>

I<set_notification_callback()>

I<set_error_callback()>

These methods set the callback functions which are invoked whenever the
peer receives the corresponding BGP message type from its peer. They
can be set in the constructor as well as with these methods. These methods
each take one argument, which is the subroutine reference to be invoked.
A callback function can be removed by calling the corresponding one of these
methods and passing it the perl I<undef> value. For callback definition and
invocation conventions see L<"CALLBACK FUNCTIONS"> later in this manual.

I<add_timer()> - add a program defined timer callback function

    $peer->add_timer(\&my_minute_timer, 60);

This method sets a program defined timer which invokes the specified callback
function when the timer expires. It takes two arguments: the first is a code
reference to the subroutine to be invoked when the timer expires, and the
second is the timer interval, in seconds. The program may set as many timers
as needed, and multiple timer callbacks may share the same interval. Program
timers add an asynchronous means for user code to gain control of the program
control flow - without them user code would only be invoked whenever BGP
events exposed by the module occur. They may be used to perform any necessary
action - for example, sending UPDATEs, starting or stopping the peering
session, house-keeping, etc.

I<remove_timer()> - remove a program defined timer callback function

    $peer->remove_timer(\&my_minute_timer);

This method removes a program defined timer callback which has been previously
set with the I<add_timer()> method. It takes a single argument: a reference
to the subroutine previously added.

=head1 CALLBACK FUNCTIONS

Whenever a B<Net::BGP4::Peer> object receives one of the BGP protocol messages -
OPEN, KEEPALIVE, UPDATE, or NOTIFICATION - from its peer, or whenever it
encounters an error condition and must send a NOTIFICATION message to its peer,
the peer object will invoke a program defined callback function corresponding
to the event type, if one has been provided, to inform the application about
the event. These callback functions are installed as described in the preceding
section of the manual. Whenever any callback function is invoked, it is passed
one or more arguments, depending on the BGP message type associated with the
callback. The first argument passed to all of the callbacks is a reference
to the B<Net::BGP4::Peer> object which the application may use to identify
which peer has signalled the event and to take appropriate action. For OPEN
and KEEPALIVE callbacks, this is the only argument passed. It is very unlikely
that applications will be interested in OPEN and KEEPALIVE events, since the
B<Net::BGP4> module handles all details of OPEN and KEEPALIVE message processing
in order to establish and maintain BGP sessions. Callback handling for these
messages is mainly included for the sake of completeness. For UPDATE and
NOTIFICATION messages, however, most applications will install callback handlers.
Whenever an UPDATE, NOTIFICATION, or error handler is called, the object will
pass a second argument. In the former case, this is a B<Net::BGP4::Update> object
encapsulating the information contained in the UPDATE message, while in the latter
two cases it is a B<Net::BGP4::Notification> object encapsulating the information
in the NOTIFICATION message sent or received.

Whenever a callback function is to be invoked, the action occuring internally is
the invocation of one of the following methods, corresponding to the event which
has occured:

I<open_callback()>

I<keepalive_callback()>

I<update_callback()>

I<notification_callback()>

I<error_callback()>

Internally, each of these methods just checks to see whether a program defined
callback function has been set and calls it if so, passing it arguments as
described above. As an alternative to providing subroutine references to the
constructor or through the I<set_open_callback()>, I<set_keepalive_callback()>,
I<set_update_callback()>, I<set_notification_callback()>, and I<set_error_callback()>
methods, an application may effect a similar result by sub-classing the
B<Net::BGP4::Peer> module and overridding the defintions of the above methods
to perform whatever actions would have been executed by ordinary callback functions.
The overridden methods are passed the same arguments as the callback functions.
This method might offer an advantage in organizing code according to different
derived classes which apply specifc routing policies.

=head1 ERROR HANDLING

There are two possibilities for error handling callbacks to be invoked. The first
case occurs when the peer receives a NOTIFICATION messages from its peer. The
second case occurs when the peer detects an error condition while processing an
incoming BGP message or when some other protocol covenant is violated - for
example if a KEEPALIVE or UPDATE message is not received before the peer's
Keepalive timer expires. In this case, the peer responds by sending a NOTIFICATION
message to its peer. In the former case the I<notification_callback()> method
is invoked as described above to handle the error, while in the latter the
I<error_callback()> method is invoked to inform the application that it has
encountered an error. Both methods are passed a B<Net::BGP4::Notification>
object encapsulating the details of the error. In both cases, the transport-layer
connection and BGP session are closed and the peer transitions to the Idle state.
The error handler callbacks can examine the cause of the error and take appropriate
action. This could be to attempt to re-establish the session (perhaps after
sleeping for some amount of time), or to unregister the peer object from the
B<Net::BGP4::Process> object and permanently end the session (for the duration
of the application's running time), or to log the event to a file on the host
system, or some combination of these or none.

=head1 SEE ALSO

B<Net::BGP4>, B<Net::BGP4::Process>, B<Net::BGP4::Update>,
B<Net::BGP4::Notification>

=head1 AUTHOR

Stephen J. Scheck <code@neurosphere.com>

=cut

## End Package Net::BGP4::Peer ##

1;
