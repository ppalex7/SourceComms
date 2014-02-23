<?php
class CommsPlugin extends SBPlugin
{
    private static $_defaultSettings = array(
       #'sourcebans__max__settings_length'
        'sourcecomms_show_on_dashboard'     => 1,
        'sourcecomms_use_immunity'          => 0,
    );

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
        return '1.0.921';
    }

    public function getUrl()
    {
        return 'https://github.com/d-ai/SourceComms';
    }


    public function init()
    {
        SourceBans::app()->on('app.beginRequest', array($this, 'onBeginRequest'));
        SourceBans::app()->on('app.beforeAction', array($this, 'onBeforeAction'));
        SourceBans::app()->on('app.beforeRender', array($this, 'onBeforeRender'));
    }

    public function runInstall()
    {
        Yii::import($this->getPathAlias('models.*'));

        // Cleanup cache
        Yii::app()->db->schema->getTables();
        Yii::app()->db->schema->refresh();

        // doesn't affects changing tables structure :(
        $transaction = Yii::app()->db->beginTransaction();

        try {
            // Checks database for old/another table versions
            if (Yii::app()->db->createCommand()->setText("SHOW TABLES LIKE '{{comms}}'")->queryScalar() !== false) {
                Yii::log('Founded old {{comms}} table in database', CLogger::LEVEL_WARNING, 'Sourcecomms');

                if (Yii::app()->db->createCommand()->select('*')->from('{{comms}}')->limit(1)->queryScalar() !== false) {
                    $new_table_name = 'old_comms_' . time();
                    Yii::log('Old table contains data and will be renamed to ' . $new_table_name, CLogger::LEVEL_WARNING, 'Sourcecomms');
                    Yii::app()->db->createCommand()->renameTable('{{comms}}', $new_table_name);

                    // If it was table of the same comms version - We can't create new table with the same foreign keys
                    if (CommsForImport::isTableValidForModel($new_table_name)) {
                        Yii::app()->db->createCommand()->dropForeignKey('comms_admin', $new_table_name);
                        Yii::app()->db->createCommand()->dropForeignKey('comms_server', $new_table_name);
                        Yii::app()->db->createCommand()->dropForeignKey('comms_unban_admin', $new_table_name);
                    }
                } else {
                    Yii::log('Old table is empty and will be dropped', CLogger::LEVEL_WARNING, 'Sourcecomms');
                    Yii::app()->db->createCommand()->dropTable('{{comms}}');
                }
            }

            // Creates new table
            Yii::app()->db->createCommand()->createTable('{{comms}}', array(
                'id' => 'mediumint(8) unsigned NOT NULL AUTO_INCREMENT PRIMARY KEY',
                'type' => 'tinyint(1) unsigned NOT NULL DEFAULT 0',
                'steam_account_id' => 'int(10) unsigned NOT NULL',
                'name' => 'varchar(64) DEFAULT NULL',
                'reason' => 'varchar(255) NOT NULL',
                'length' => 'mediumint(8) NOT NULL DEFAULT -1',
                'server_id' => 'smallint(5) unsigned DEFAULT NULL',
                'admin_id' => 'smallint(5) unsigned DEFAULT NULL',
                'admin_ip' => 'varchar(15) NOT NULL',
                'unban_admin_id' => 'smallint(5) unsigned DEFAULT NULL',
                'unban_reason' => 'varchar(255) DEFAULT NULL',
                'unban_time' => 'int(10) unsigned DEFAULT NULL',
                'create_time' => 'int(10) unsigned NOT NULL',
                'KEY steam (steam_account_id)',
                'KEY server_id (server_id)',
                'KEY admin_id (admin_id)',
                'CONSTRAINT comms_admin FOREIGN KEY (admin_id) REFERENCES {{admins}} (id) ON DELETE SET NULL',
                'CONSTRAINT comms_server FOREIGN KEY co(server_id) REFERENCES {{servers}} (id) ON DELETE SET NULL',
                'CONSTRAINT comms_unban_admin FOREIGN KEY (unban_admin_id) REFERENCES {{admins}} (id) ON DELETE SET NULL'
            ), 'ENGINE=InnoDB DEFAULT CHARSET=utf8');

            $transaction->commit();
            return true;
        }

        catch (Exception $e) {
            Yii::log('Sourcecomms installation failed', CLogger::LEVEL_ERROR, 'Sourcecomms');
            Yii::log($e->getMessage(), CLogger::LEVEL_ERROR, 'Sourcecomms');

            $transaction->rollback();
            return false;
        }
    }

    public function runUninstall()
    {
        $transaction = Yii::app()->db->beginTransaction();

        try {
            Yii::app()->db->createCommand()->dropTable('{{comms}}');

            $transaction->commit();
            return true;
        }

        catch(Exception $e) {
            $transaction->rollback();
            return false;
        }
    }

    public function onBeginRequest($event)
    {
        // Import plugin models
        Yii::import($this->getPathAlias('models.*'));
        // Get and register assets path
        $assetsUrl = Yii::app()->assetManager->publish($this->getPath('assets'));
        // Register custom css file
        Yii::app()->clientScript->registerCssFile($assetsUrl . '/css/sourcecomms.css');

        // Register controller
        Yii::app()->controllerMap['comms'] = $this->getPathAlias('controllers.CommsController');

        // Add URL rule
        Yii::app()->urlManager->addRules(
            array(
                'comms'         => 'comms/index',
                'admin/comms'   => 'comms/admin'
            ),
            false
        );

        // Add permissions
        SourceBans::app()->permissions->add('ADD_COMMS',        Yii::t('CommsPlugin.permissions', 'Ban communication'));
        SourceBans::app()->permissions->add('EDIT_OWN_COMMS',   Yii::t('CommsPlugin.permissions', 'Edit own communication punishments'));
        SourceBans::app()->permissions->add('EDIT_GROUP_COMMS', Yii::t('CommsPlugin.permissions', 'Edit group communication punishments'));
        SourceBans::app()->permissions->add('EDIT_ALL_COMMS',   Yii::t('CommsPlugin.permissions', 'Edit all communication punishments'));
        SourceBans::app()->permissions->add('UNBAN_OWN_COMMS',  Yii::t('CommsPlugin.permissions', 'Unban own communication punishments'));
        SourceBans::app()->permissions->add('UNBAN_GROUP_COMMS',Yii::t('CommsPlugin.permissions', 'Unban group communication punishments'));
        SourceBans::app()->permissions->add('UNBAN_ALL_COMMS',  Yii::t('CommsPlugin.permissions', 'Unban all communication punishments'));
        SourceBans::app()->permissions->add('DELETE_COMMS',     Yii::t('CommsPlugin.permissions', 'Delete communication punishments'));

        // Load plugin settings
        foreach (self::$_defaultSettings as $name => $value) {
            if (!SourceBans::app()->settings->contains($name)) {
                $setting = new SBSetting();
                $setting->name = $name;
                $setting->value = $value;
                if (!$setting->save())
                    Yii::log('Error saving new Sourcecomms setting "' . $name . '"', CLogger::LEVEL_ERROR, 'Sourcecomms');
                else
                    Yii::log('Saved new Sourcecomms setting "' . $name . '" with value "' . $value . '"', CLogger::LEVEL_INFO, 'Sourcecomms');
            }
        }
    }

    public function onBeforeAction($action)
    {
        static $loaded;

        if(!isset($loaded)) {
            // Add header tab
            Yii::app()->controller->tabs[] = array(
                'label' => Yii::t('CommsPlugin.main', 'Comms'),
                'url' => array('comms/index'),
                'linkOptions' => array(
                    'title' => Yii::t('CommsPlugin.main', 'All of the communication punishments (such as chat gags and voice mutes) in the database can be viewed from here.')
                ),
            );
            $loaded = true;
        }

        return true;
    }

    public function onBeforeRender($event)
    {
        switch(Yii::app()->controller->route) {
            case 'admin/index':
                // Add Comms to Adminitstration page menu
                if (!Yii::app()->user->isGuest && Yii::app()->user->data->hasPermission('ADD_COMMS', 'OWNER')) {
                    Yii::app()->controller->menu[] = array(
                        'label' => Yii::t('CommsPlugin.main', 'Comms'),
                        'url' => array('admin/comms'),
                        'itemOptions' => array('class'=>'comms'),
                        'visible' => true,
                    );
                }

                // Add Comms stat to admin dashboard
                $model = new Comms;

                $script = Yii::app()->controller->renderPartial(
                    $this->getViewFile('_admin_dashboard'),
                    array(
                        'total_mutes'   => $model->countByAttributes(array('type' => Comms::MUTE_TYPE)),
                        'total_gags'    => $model->countByAttributes(array('type' => Comms::GAG_TYPE)),
                    ),
                    true
                );
                Yii::app()->clientScript->registerScript('admin_index_commsStats',
                    '$("html>body#admin_index>div.container>div.row>div.span8>table.table.table-stat>tbody>tr").eq(2).after("' . CJavaScript::quote($script) . '");',
                    CClientScript::POS_READY);
                break;

            case 'site/bans':
                // Add 'Block Comms' link to each ban details
                break;
        }
    }
}
