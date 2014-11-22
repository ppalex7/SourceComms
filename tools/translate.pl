#!/usr/bin/perl

use warnings;
use strict;

use File::Slurp qw/edit_file_lines/;

print "Bumping plugin version\n";
edit_file_lines {
    if ($_ =~ m/^\s+return\s+'\d+\.\d+\.(\d+)';$/) {
        my $build = $1;
        $build++;
        $_ =~ s/\.\d+';$/.$build';/
    }
} '/Users/alex/Code/SourceComms/web_upload/application/plugins/SourceComms/CommsPlugin.php';


print "Extcract translations\n";
system ('php /Users/alex/Code/SourceBans/web/framework/yiic message /Users/alex/Code/SourceComms/web_upload/application/plugins/SourceComms/messages/config.php') == 0 or die "An error occurred\n";

print "Delete not-sourcecomms translation files\n";
system ('rm /Users/alex/sc/web_upload/application/plugins/SourceComms/messages/*/sourcebans.php') == 0 or die;
system ('rm /Users/alex/sc/web_upload/application/plugins/SourceComms/messages/*/zii.php') == 0 or die;
system ('rm /Users/alex/sc/web_upload/application/plugins/SourceComms/messages/*/yii.php') == 0 or die;

print "All done\n";
exit;
