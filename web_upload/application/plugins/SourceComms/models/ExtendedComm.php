<?php
/**
 * This is the model class for old sourcecomms table.
 *
 * @author Alex
 * @copyright (C)2014 Alexandr Duplishchev.
 * @link https://github.com/d-ai/SourceComms
 *
 * The followings are the available columns in table 'extendedcomm':
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
class ExtendedComm extends CActiveRecord
{
    const GAG_TYPE  = 2;
    const MUTE_TYPE = 1;
    const COMM_TIME = 1;
    const COMM_PERM = 2;

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
        if ($this->_tableName)
            return $this->_tableName;
        else
            return 'extendedcomm';
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
                  === array('steam_id',
                            'mute_type',
                            'mute_length',
                            'mute_admin',
                            'mute_time',
                            'mute_reason',
                            'mute_level',
                            'gag_type',
                            'gag_length',
                            'gag_admin',
                            'gag_time',
                            'gag_reason',
                            'gag_level',
                      );
    }

    /**
     * @var $availableRelations - Array of relations which could be used at import
     */
    public static $availableRelations = array();

    /**
     * @var integer punishment type
     * @return boolean - whether the record is valid
     */
    private function isValid($type)
    {
        return preg_match(SourceBans::PATTERN_STEAM, $this->steam_id)
               && (     $type == self::GAG_TYPE
                        && ($this->gag_type == self::COMM_TIME
                            || $this->gag_type == self::COMM_PERM)
                    ||  $type == self::MUTE_TYPE
                        && ($this->mute_type == self::COMM_TIME
                            || $this->mute_type == self::COMM_PERM)
                  );
    }

    /**
     * @return integer steam account id
     */
    public function getSteamAccountID()
    {
        return substr($this->steam_id, 8, 1) + 2 * substr($this->steam_id, 10, 10);
    }

    /**
     * @var integer punishment type
     * @return integer length of punishment in minutes
     */
    private function getLength($type)
    {
        switch ($type)
        {
            case self::GAG_TYPE:
                $length = $this->gag_length;
                break;
            case self::MUTE_TYPE:
                $length = $this->mute_length;
                break;
            default:
                $length = -1;
                break;
        }

        if ($length > 0)
            return (int) $length / 60;
        else if ($length == 0)
            return 0;
        else
            return -1;
    }

    /**
     * @var integer punishment type
     * @return integer creation time
     */
    private function getCreateTime($type)
    {
        switch ($type)
        {
            case self::GAG_TYPE:
                return $this->gag_time;
            case self::MUTE_TYPE:
                return $this->mute_time;
            default:
                return null;
        }
    }

    /**
     * @var integer punishment type
     * @return string punishment reason
     */
    private function getReason($type)
    {
        switch ($type)
        {
            case self::GAG_TYPE:
                return $this->gag_reason;
            case self::MUTE_TYPE:
                return $this->mute_reason;
            default:
                return null;
        }
    }

    /**
     * @var integer punishment type
     * @return array attributes for search the related Comms model
     */
    private function getAttributesForSearch($type)
    {
        if ($this->isValid($type))
            return array(
                'type'              => $type,
                'steam_account_id'  => $this->getSteamAccountID(),
                'create_time'       => $this->getCreateTime($type),
            );
        else
            return null;
    }

    /**
     * @var integer punishment type
     * @return array attributes for saving to new Comms record
     */
    private function getAttributesForSave($type)
    {
        if ($this->isValid($type))
            return array(
                'type'              => $type,
                'steam_account_id'  => $this->getSteamAccountID(),
                'name'              => null,
                'reason'            => $this->getReason($type) ? $this->getReason($type) : Yii::t('CommsPlugin.main', 'Imported from ExtendedComm'),
                'length'            => $this->getLength($type),
                'server_id'         => null,
                'admin_id'          => null,
                'admin_ip'          => $_SERVER['SERVER_ADDR'],
                'unban_admin_id'    => null,
                'unban_reason'      => null,
                'unban_time'        => null,
                'create_time'       => $this->getCreateTime($type),
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
                'search' => $this->getAttributesForSearch(self::GAG_TYPE),
                'save'   => $this->getAttributesForSave(self::GAG_TYPE),
            ),
            array(
                'search' => $this->getAttributesForSearch(self::MUTE_TYPE),
                'save'   => $this->getAttributesForSave(self::MUTE_TYPE),
            ),
        );
    }
}
