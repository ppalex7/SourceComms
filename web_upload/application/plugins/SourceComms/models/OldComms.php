<?php
/**
 * This is the model class for old sourcecomms table.
 *
 * @author Alex
 * @copyright (C)2014 Alexandr Duplishchev.
 * @link https://github.com/d-ai/SourceComms
 *
 * The followings are the available columns in table '{{comms}}':
 * @property integer $bid ID
 * @property string $authid SteamID
 * @property string $name Name
 * @property integer $created creation Date/Time
 * @property integer $ends ends Date/Time
 * @property integer $length Length in seconds
 * @property string $reason Reason
 * @property integer $aid Admin ID
 * @property string $adminIp Admin IP address
 * @property integer $sid Server ID
 * @property integer $RemovedBy Unbanned by Admin ID
 * @property string $RemoveType Unban type
 * @property integer $RemovedOn Unbanned on Date/Time
 * @property integer $type Type
 * @property string $ureason Unban reason
 *
 * The followings are the available model relations:
 * @property SBAdmin $admin Admin
 * @property SBServer $server Server
 * @property SBAdmin $unban_admin Unban admin
 */
class OldComms extends CActiveRecord
{
    const GAG_TYPE  = 2;
    const MUTE_TYPE = 1;

    const REMOVED_BY_ADMIN = 'U';

    /**
     * @var $_tableName - Name of table which is associated with model
     */
    protected $_tableName;

    /**
     * Returns the static model of the specified AR class.
     * @param string $className active record class name.
     * @return Comms the static model class
     */
    public static function model($className=__CLASS__, $table)
    {
        return parent::model($className);
    }

    /**
     * Constructor.
     * @param $scenario - scenario name
     * @param $tableName - name of source table for creating model.
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
        return $this->_tableName;
    }

    /**
     * Checks table in the database for the compatibility with this model.
     * @param string $table - name of table for check
     * @return boolean - whether the table is compatible
     */
    public static function isTableValidForModel($table)
    {
        return in_array($table, Yii::app()->db->getSchema()->getTableNames(), true)
               && Yii::app()->db->getSchema()->getTable($table)->getColumnNames()
                  === array('bid',
                            'authid',
                            'name',
                            'created',
                            'ends',
                            'length',
                            'reason',
                            'aid',
                            'adminIp',
                            'sid',
                            'RemovedBy',
                            'RemoveType',
                            'RemovedOn',
                            'type',
                            'ureason',
                      );
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
            'admin' => array(self::BELONGS_TO, 'SBAdmin', 'aid'),
            'server' => array(self::BELONGS_TO, 'SBServer', 'sid'),
            'unban_admin' => array(self::BELONGS_TO, 'SBAdmin', 'RemovedBy'),
        );
    }

    /**
     * @return boolean - whether the record is valid
     */
    private function isValid()
    {
        return preg_match(SourceBans::STEAM_PATTERN, $this->authid)
               && ($this->type == self::GAG_TYPE
                   || $this->type == self::MUTE_TYPE
                  );
    }

    /**
     * @return integer steam account id
     */
    public function getSteamAccountID()
    {
        return substr($this->authid, 8, 1) + 2 * substr($this->authid, 10, 10);
    }

    /**
     * @return integer length of punishment in minutes
     */
    private function getLength()
    {
        if ($this->length > 0)
            return (int) $this->length / 60;
        else if ($this->length == 0)
            return 0;
        else
            return -1;
    }

    /**
     * @return array attributes for search the related Comms model
     */
    private function getAttributesForSearch()
    {
        if ($this->isValid())
            return array(
                'type'              => $this->type,
                'steam_account_id'  => $this->getSteamAccountID(),
                'create_time'       => $this->created,
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
                'steam_account_id'  => $this->getSteamAccountID(),
                'name'              => $this->name ? $this->name : null,
                'reason'            => $this->reason ? $this->reason : Yii::t('CommsPlugin.main', 'Imported from previous SourceComms version'),
                'length'            => $this->getLength(),
                'server_id'         => $this->server ? $this->server->id : null,
                'admin_id'          => $this->admin ? $this->admin->id : null,
                'admin_ip'          => ($this->admin || $this->aid == 0) ? $this->adminIp : $_SERVER['SERVER_ADDR'],
                'unban_admin_id'    => ($this->RemoveType == self::REMOVED_BY_ADMIN && $this->unban_admin) ? $this->unban_admin->id : null,
                'unban_reason'      => ($this->RemoveType == self::REMOVED_BY_ADMIN && $this->ureason) ? $this->ureason : null,
                'unban_time'        => ($this->RemoveType == self::REMOVED_BY_ADMIN && $this->RemovedOn) ? $this->RemovedOn : null,
                'create_time'       => $this->created,
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
