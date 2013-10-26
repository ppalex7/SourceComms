<?php
class CommsPlugin extends SBPlugin
{
    public function getName()
    {
        return 'SourceComms';
    }

    public function getDescription()
    {
        return Yii::t('CommsPlugin.main', 'Extended, temporary and permanent punishments');
    }

    public function getAuthor()
    {
        return 'ppalex';
    }

    public function getVersion()
    {
        return '1.0.29';
    }

    public function getUrl()
    {
        return 'https://github.com/d-ai/SourceComms';
    }


    public function init()
    {
        SourceBans::app()->on('app.beginRequest', array($this, 'onBeginRequest'));
    }

    public function runInstall()
    {
        $transaction = Yii::app()->db->beginTransaction();

        try {
            Yii::app()->db->createCommand()->createTable('{{comms}}', array(
                'id' => 'mediumint(8) unsigned NOT NULL AUTO_INCREMENT PRIMARY KEY',
                'type' => 'tinyint(1) unsigned NOT NULL DEFAULT 0',
                'steam_account_id' => 'int(10) unsigned NOT NULL',
                'name' => 'varchar(64) DEFAULT NULL',
                'reason' => 'varchar(255) NOT NULL',
                'length' => 'mediumint(8) unsigned NOT NULL DEFAULT 0',
                'server_id' => 'smallint(5) unsigned DEFAULT NULL',
                'admin_id' => 'smallint(5) unsigned DEFAULT NULL',
                'admin_ip' => 'varchar(15) NOT NULL',
                'unban_admin_id' => 'smallint(5) unsigned DEFAULT NULL',
                'unban_reason' => 'varchar(255) DEFAULT NULL',
                'unban_time' => 'int(10) unsigned DEFAULT NULL',
                'create_time' => 'int(10) unsigned NOT NULL DEFUALT CURRENT_TIMESTAMP',
                'KEY steam_unbanned (steam_account_id,unban_admin_id)',
                'KEY server_id (server_id)',
                'KEY admin_id (admin_id)',
            ), 'ENGINE=InnoDB DEFAULT CHARSET=utf8');
            $transaction->commit();
            return true;
        }

        catch(Exception $e)
        {
            $transaction->rollback();
            return false;
        }
    }

    public function runUninstall()
    {
        $transaction = Yii::app()->db->beginTransaction();

        try
        {
            Yii::app()->db->createCommand()->dropTable('{{comms}}');

            $transaction->commit();
            return true;
        }

        catch(Exception $e)
        {
            $transaction->rollback();
            return false;
        }
    }

    public function onBeginRequest($event)
    {
        // Register controller
        Yii::app()->controllerMap['comms'] = $this->getPathAlias('controllers.CommsController');

        // Add URL rule
        Yii::app()->urlManager->addRules(array(
            'comms' => 'comms/index',
        ), false);
    }

    public function onBeforeAction($action)
    {
        // Add header tab
        Yii::app()->controller->tabs[] = array(
            'label' => Yii::t('CommsPlugin.main', 'Comms'),
            'url' => array('comms/index'),
        );
    }
}
