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
}
