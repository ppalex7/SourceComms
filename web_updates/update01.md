# Updating web-part to `16th March 2013` version

Please update following files:
* [/pages/page.commslist.php](https://raw.github.com/d-ai/SourceComms/master/web_upload/pages/page.commslist.php)
* [/themes/default/page_comms.tpl](https://raw.github.com/d-ai/SourceComms/master/web_upload/themes/default/page_comms.tpl)
* [/themes/sourcebans_dark/page_comms.tpl](https://raw.github.com/d-ai/SourceComms/master/web_upload/themes/sourcebans_dark/page_comms.tpl)

Run the following sql queries on your database (<b>make sure</b> that your database tables prefix is **sb**):

	ALTER TABLE sb_comms DROP INDEX reason;
	ALTER TABLE sb_comms DROP INDEX authid_2;
	ALTER TABLE sb_comms DROP INDEX name;
