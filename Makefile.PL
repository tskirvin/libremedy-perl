use ExtUtils::MakeMaker;

opendir (SCRIPTS, 'bin') or die "couldn't open 'bin': $!\n";
my @scripts = grep { /^[^\.]/ } readdir SCRIPTS;
closedir SCRIPTS;

WriteMakefile(
    NAME              => 'Remedy',
    DISTNAME          => 'Remedy',
    ABSTRACT_FROM     => "lib/Remedy.pm",
    dist              => { COMPRESS => 'gzip', SUFFIX => 'gz' },
    VERSION_FROM      => 'lib/Remedy.pm', 
    EXE_FILES         => [ @scripts ],
    AUTHOR            => 'Tim Skirvin <tskirvin@stanford.edu>',
    PREREQ_PM         => { 
      'Stanford::Remedy'    => '0.12',
      'Lingua::EN::Inflect' => '1.89',
      'Date::Parse'         => '2.27',
      'Log::Log4perl'       => '1.07',
      'Text::Wrap'          => '2005',
                         }, 
);
