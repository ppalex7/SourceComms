<?php
/**
 * This is the model class for table of sourcecomms same version.
 *
 * @author Alex
 * @copyright (C)2013-2014 Alexandr Duplishchev.
 * @link https://github.com/d-ai/SourceComms
 *
 * The followings are the available columns in table '{{comms}}':
 * @property integer $id ID
 * @property integer $type Type
 * @property string $steam_account_id Steam Account ID
 * @property string $name Name
 * @property string $reason Reason
 * @property integer $length Length
 * @property integer $server_id Server ID
 * @property integer $admin_id Admin ID
 * @property string $admin_ip Admin IP address
 * @property integer $unban_admin_id Unbanned by
 * @property string $unban_reason Unban reason
 * @property integer $unban_time Unbanned on
 * @property integer $create_time Date/Time
 *
 * The followings are the available model relations:
 * @property SBAdmin $admin Admin
 * @property SBServer $server Server
 * @property SBAdmin $unban_admin Unban admin
 */
class CommsForImport extends CActiveRecord
{
    const TYPE_GAG  = 2;
    const TYPE_MUTE = 1;

    /**
     * @var string - Name of table which is associated with model
     */
    protected $_tableName;

    /**
     * Checks table in the database for the compatibility with this model.
     * @param string $table - name of table for check
     * @return boolean - whether the table is compatible
     */
    public static function isTableValidForModel($table)
    {
        return in_array($table, Yii::app()->db->getSchema()->getTableNames(), true)
               && Yii::app()->db->getSchema()->getTable($table)->getColumnNames()
                  === array('id',
                            'type',
                            'steam_account_id',
                            'name',
                            'reason',
                            'length',
                            'server_id',
                            'admin_id',
                            'admin_ip',
                            'unban_admin_id',
                            'unban_reason',
                            'unban_time',
                            'create_time',
                      );
    }

    /**
     * Returns the static model of the specified AR class.
     * @param string $className active record class name.
     * @return Comms the static model class
     */
    public static function model($className=__CLASS__)
    {
        return parent::model($className);
    }

    /**
     * Constructor.
     * @param $scenario - scenario name
     * @param $tableName - name of source table for created model.
     */
    public function __construct($scenario = 'insert', $tableName = null)
    {
        $this->_tableName = $tableName;
        parent::__construct($scenario);
    }

    /**
     * @return string the associated database table name
     */
    public function tableName()
    {
        if ($this->_tableName)
            return $this->_tableName;
        else
            return '{{comms_old}}';
    }

    /**
     * @var $availableRelations - Array of relations which could be used at import
     */
    public static $availableRelations = array('admin','server','unban_admin');

    /**
     * @return array relational rules.
     */
    public function relations()
    {
        // NOTE: you may need to adjust the relation name and the related
        // class name for the relations automatically generated below.
        return array(
            'admin' => array(self::BELONGS_TO, 'SBAdmin', 'admin_id'),
            'server' => array(self::BELONGS_TO, 'SBServer', 'server_id'),
            'unban_admin' => array(self::BELONGS_TO, 'SBAdmin', 'unban_admin_id'),
        );
    }

    /**
     * @return boolean - whether the record is valid
     */
    private function isValid()
    {
        return $this->steam_account_id
               && ($this->type == self::TYPE_GAG
                   || $this->type == self::TYPE_MUTE
                  );
    }

    /**
     * @return array attributes for search the related Comms model
     */
    private function getAttributesForSearch()
    {
        if ($this->isValid())
            return array(
                'type'              => $this->type,
                'steam_account_id'  => $this->steam_account_id,
                'create_time'       => $this->create_time,
            );
        else
            return null;
    }

    /**
     * @return array attributes for saving to new Comms record
     */
    private function getAttributesForSave()
    {
        if ($this->isValid())
            return array(
                'type'              => $this->type,
                'steam_account_id'  => $this->steam_account_id,
                'name'              => $this->name ? $this->name : null,
                'reason'            => $this->reason ? $this->reason : Yii::t('CommsPlugin.main', 'Imported from same SourceComms version'),
                'length'            => $this->length >= 0 ? $this->length : -1,
                'server_id'         => $this->server ? $this->server->id : null,
                'admin_id'          => $this->admin ? $this->admin->id : null,
                'admin_ip'          => $this->admin_ip ? $this->admin_ip : $_SERVER['SERVER_ADDR'],
                'unban_admin_id'    => ($this->unban_time && $this->unban_admin) ? $this->unban_admin->id : null,
                'unban_reason'      => ($this->unban_time && $this->unban_reason) ? $this->unban_reason : null,
                'unban_time'        => $this->unban_time ? $this->unban_time : null,
                'create_time'       => $this->create_time,
            );
        else
            return null;
    }

    /**
     * @return array of arrays of attributes for search and saving Comms model
     */
    public function getDataForImport()
    {
        return array(
            array(
                'search' => $this->getAttributesForSearch(),
                'save'   => $this->getAttributesForSave(),
            ),
        );
    }
}
