#!/usr/bin/perl

use warnings;
use strict;

use FindBin qw/$Bin/;
sub p;

my $develop = '0.9-develop';

chdir "$Bin/../" or die $!;

# Проверим ветку и состояние рабочей копии
my @git_status = split /\n/, qx/git status/;
die "You must be on branch '$develop'\n" unless $git_status[0] =~ m/^(?:# )?On branch $develop$/;
die "You have changes in working copy. Exiting...\n" unless $git_status[3] =~ m/nothing to commit|Your branch is ahead of/;

# Определим версию плагина
open (my $plugin_file, '<', "$Bin/../game_upload/scripting/sourcecomms.sp") or die "Can't open plugin file: $!\n";
my $plugin_version;
while (my $line = <$plugin_file>) {
    next unless $line =~ m/#define PLUGIN_VERSION "([0-9\.]+)"/;
    $plugin_version = $1;
    last;
}
close $plugin_file;
print "SourceComms version $plugin_version\n";

open (my $update_file, '>:utf8', "$Bin/../sc-updatefile.txt") or die "Can't open update file: $!\n";
p q/"Updater"/;
p q/{/;
p qq/\t"Information"/;
p qq/\t{/;
p qq/\t\t"Version"/;
p qq/\t\t{/;
p qq/\t\t\t"Latest"\t"$plugin_version"/;
p qq/\t\t}/;
p;
p qq!\t\t"Notes"\t"More info @ https://github.com/d-ai/SourceComms/blob/master/CHANGELOG.md or https://forums.alliedmods.net/showthread.php?t=207176 "!;
p qq/\t\t"Notes"\t" "/;
p qq/\t\t"Notes"\t" "/;
p qq/\t}/;
p;
p qq/\t"Files"/;
p qq/\t{/;
p qq!\t\t"Plugin"\t"Path_SM/plugins/sourcecomms.smx"!;
p qq!\t\t"Plugin"\t"Path_SM/scripting/sourcecomms.sp"!;
p qq!\t\t"Plugin"\t"Path_SM/scripting/include/sourcecomms.inc"!;
p qq!\t\t"Plugin"\t"Path_SM/translations/sourcecomms.phrases.txt"!;
p qq/\t}/;
p q/}/;
close $update_file;
print "Update-file draft builded\n";

die "Uploading aborted!\n" if system ('vim /Users/alex/Code/SourceComms/sc-updatefile.txt') >> 8;
print "Successfully edited update-file\n";


print "Let's do merge!\n";
system ('git checkout master') == 0 or die "Can't switch to master branch\n";
system ("git merge $develop --no-ff --message 'Updated to version $plugin_version'") == 0 or die "An error occurred during merging\n";
system ("git tag -a '$plugin_version'") == 0 or die "An error occurred during tag adding\n";
system ('git push --all') == 0 or die "An error occurred during pushing branches\n";
system ('git push --tags') == 0 or die "An error occurred during pushing tags\n";

print "Let's make zip files\n";
chdir "$Bin/../game_upload" or die $!;
system ('zip -r ../sourcecomms-srv.zip *') == 0 or die "An error occurred during archiving game server files\n";
chdir "$Bin/../web_upload" or die $!;
system ('zip -r ../sourcecomms-web.zip *') == 0 or die "An error occurred during archiving web files\n";

print "Uploading files to hosting\n";
system ('sftp -b /Users/alex/Code/SourceComms/tools/upload.batch web@vps') == 0 or die "An error occurred during uploading\n";

# Переключаемся обратно на develop
system ('git checkout $develop') == 0 or die "Can't switch to $develop branch\n";

chdir "$Bin/../" or die $!;
print "All done\n";
exit;

sub p {
    print {$update_file} @_, "\n";
}
