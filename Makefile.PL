use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    'NAME'		=> 'Net::BGP4',
    'ABSTRACT'		=> 'BGP4 speaker/listener API',
    'AUTHOR'		=> 'Stephen J. Scheck <code@neurosphere.com>',
    'VERSION_FROM'	=> 'lib/Net/BGP4.pm', # finds $VERSION
    'PREREQ_PM'		=> {}, # e.g., Module::Name => 1.1
);
