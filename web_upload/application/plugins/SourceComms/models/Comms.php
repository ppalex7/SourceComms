<?php
/**
 * This is the model class for table "{{comms}}".
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
 * @property boolean $isActive Whether the ban is active
 * @property boolean $isExpired Whether the ban is expired
 * @property boolean $isPermanent Whether the ban is permanent
 * @property boolean $isTemporary Whether the ban is temporary
 * @property boolean $isUnbanned Whether the ban is unbanned
 * @property string $steam SteamID
 * @property integer $communityId Steam Community ID
 * @property string $adminName admin name or CONSOLE
 * @property string $lengthText formatted punishment length
 * @property string $expireText formatted punishment expire date/time
 *
 * The followings are the available model relations:
 * @property SBAdmin $admin Admin
 * @property SBServer $server Server
 * @property SBAdmin $unban_admin Unban admin
 * @property SBComment[] $comments Comments
 */
class Comms extends CActiveRecord
{
    const GAG_TYPE  = 2;
    const MUTE_TYPE = 1;
    const COMMENTS_TYPE = 'C';

    /**
     * @var array with supported punishment types.
     */
    private static $_types;

    /**
     * @var array with icons for supported punishment types.
     */
    private static $_icons;

    /**
     * @var string with json translations for unban confirmation window.
     */
    private static $_unban_translations;

    /**
     * @var string - Name of table which is associated with model
     */
    protected $_tableName;

    /**
     * @var boolean - is this records was internally created
     */
    public $isInternalRecord = false;

    /**
     * Returns the supported punishment types
     * @return array the supported punishment types
     */
    public static function getTypes()
    {
        if (self::$_types === null)
            self::$_types = array(
                self::GAG_TYPE  => Yii::t('CommsPlugin.main', 'Gag'),
                self::MUTE_TYPE => Yii::t('CommsPlugin.main', 'Mute'),
            );

        return self::$_types;
    }

    /**
     * Returns translated string for js code
     * @return string json encoded translations
     */
    public static function getUnbanJsonTranslations()
    {
        if (self::$_unban_translations === null)
            self::$_unban_translations = CJSON::encode(array(
                self::GAG_TYPE => array(
                    'unban_reason'          => Yii::t('CommsPlugin.main', 'Ungag reason'),
                    'unban_confirmation'    => Yii::t('CommsPlugin.main', 'Please give a short comment, why you are going to ungag &laquo;__NAME__&raquo;:'),
                    'unban'                 => Yii::t('CommsPlugin.main', 'Ungag'),
                ),
                self::MUTE_TYPE => array(
                    'unban_reason'          => Yii::t('CommsPlugin.main', 'Unmute reason'),
                    'unban_confirmation'    => Yii::t('CommsPlugin.main', 'Please give a short comment, why you are going to unmute &laquo;__NAME__&raquo;:'),
                    'unban'                 => Yii::t('CommsPlugin.main', 'Unmute'),
                ),
            ));

        return self::$_unban_translations;
    }

    /**
     * Returns name of punishment type.
     * @param integer $type - Punishment Type.
     * @return string Type name
     */
    public static function getType($type)
    {
        if (array_key_exists($type, self::getTypes()))
            return self::getTypes()[$type];
        else
            return Yii::t("sourcebans", "Unknown");
    }

    /**
     * Returns relative icon path for punishment type.
     * @param integer $type - Punishment Type.
     * @param string $assetsUrl - part of path (optional).
     * @return string path to icon
     */
    public static function getIcon($type, $assetsUrl = '')
    {
        if (self::$_icons === null)
            self::$_icons = array(
                self::GAG_TYPE  => '/images/type_c.png',
                self::MUTE_TYPE => '/images/type_v.png',
            );

        if (array_key_exists($type, self::$_icons))
            return $assetsUrl . self::$_icons[$type];
        else
            return "/images/countries/unknown.gif";
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
            return '{{comms}}';
    }

    /**
     * @return array validation rules for model attributes.
     */
    public function rules()
    {
        // NOTE: you should only define rules for those attributes that
        // will receive user inputs.
        return array(
            array('steam, type, reason, length', 'required'),
            array('steam', 'match', 'pattern' => SourceBans::STEAM_PATTERN),
            array('length', 'numerical', 'integerOnly' => true),
            array('name', 'length', 'max' => 64),
            array('reason, unban_reason', 'length', 'max' => 255),
            // The following rule is used by search().
            // Please remove those attributes that should not be searched.
            array('id, type, steam_account_id, name, reason, length, server_id, admin_id, admin_ip, unban_admin_id, unban_reason, unban_time, create_time', 'safe', 'on' => 'search'),
            // custom validators
            array('type', 'validateType'),
            array('steam_account_id', 'oneActiveTypePerSteam', 'on' => 'insert, update'),
        );
    }

    /**
     * Validates attribute type
     */
    public function validateType($attribute, $params)
    {
        if ($attribute === 'type') {
            if (!array_key_exists($this->type, self::getTypes()))
                $this->addError('type', Yii::t('CommsPlugin.main', 'Invalid punishment type'));
        } else {
            throw new CException('validateType is not intended for atrribute ' . $attribute);
        }
    }

    /**
     * Checks that player doesn't have any active punishments of the same type
     */
    public function oneActiveTypePerSteam($attribute, $params)
    {
        if ($attribute === 'steam_account_id') {
            if($this->steam_account_id && ($this->isNewRecord || $this->isActive)) {
                $criteria = new CDbCriteria();
                $criteria->scopes = 'active';
                $criteria->condition = 'steam_account_id = :id AND type = :type';
                $criteria->params = array(
                    ':id'   => $this->steam_account_id,
                    ':type' => $this->type,
                );

                if (self::model()->exists($criteria)) {
                    switch ($this->type) {
                        case self::GAG_TYPE:
                            $this->addError('steam', Yii::t('CommsPlugin.main', 'Already gagged'));
                            break;
                        case self::MUTE_TYPE:
                            $this->addError('steam', Yii::t('CommsPlugin.main', 'Already muted'));
                            break;
                        default:
                            $this->addError('steam', Yii::t('CommsPlugin.main', 'Already punished'));
                            break;
                    }
                }
            }
        } else {
            throw new CException('oneActiveTypePerSteam is not intended for atrribute ' . $attribute);
        }
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
            'comments' => array(self::HAS_MANY, 'SBComment', 'object_id', 'condition' => 'object_type = :object_type', 'params' => array(':object_type' => self::COMMENTS_TYPE)),
            'commentsCount' => array(self::STAT, 'SBComment', 'object_id', 'condition' => 'object_type = :object_type', 'params' => array(':object_type' => self::COMMENTS_TYPE)),
        );
    }

    /**
     * @return array customized attribute labels (name=>label)
     */
    public function attributeLabels()
    {
        return array(
            'id' => 'ID',
            'type' => Yii::t('sourcebans', 'Type'),
            'steam' => Yii::t('sourcebans', 'Steam ID'),
            'name' => Yii::t('sourcebans', 'Name'),
            'reason' => Yii::t('sourcebans', 'Reason'),
            'length' => Yii::t('sourcebans', 'Length'),
            'server_id' => Yii::t('sourcebans', 'Server'),
            'admin_id' => Yii::t('sourcebans', 'Admin'),
            'admin_ip' => Yii::t('sourcebans', 'Admin IP address'),
            'unban_admin_id' => Yii::t('sourcebans', 'Unbanned by'),
            'unban_reason' => Yii::t('sourcebans', 'Unban reason'),
            'unban_time' => Yii::t('sourcebans', 'Unbanned on'),
            'create_time' => Yii::t('sourcebans', 'Date') . '/' . Yii::t('sourcebans', 'Time'),
            'admin.name' => Yii::t('sourcebans', 'Admin'),
        );
    }

    /**
     * Retrieves a list of models based on the current search/filter conditions.
     * @return CActiveDataProvider the data provider that can return the models based on the search/filter conditions.
     */
    public function search($criteria=array())
    {
        // Warning: Please modify the following code to remove attributes that
        // should not be searched.

        $criteria=new CDbCriteria($criteria);
        $criteria->with=array('admin','server','server.game','unban_admin');
        $criteria->compare('t.id',$this->id);
        $criteria->compare('t.type',$this->type);
        $criteria->compare('t.steam_account_id',$this->steam_account_id);
        $criteria->compare('t.name',$this->name,true);
        $criteria->compare('t.reason',$this->reason,true);
        $criteria->compare('t.length',$this->length);
        $criteria->compare('t.server_id',$this->server_id);
        $criteria->compare('t.admin_id',$this->admin_id);
        $criteria->compare('t.admin_ip',$this->admin_ip,true);
        $criteria->compare('t.unban_admin_id',$this->unban_admin_id);
        $criteria->compare('t.unban_reason',$this->unban_reason,true);
        $criteria->compare('t.unban_time',$this->unban_time);
        $criteria->compare('t.create_time',$this->create_time);

        return new CActiveDataProvider($this, array(
            'criteria'=>$criteria,
            'pagination'=>array(
                'pageSize'=>SourceBans::app()->settings->items_per_page,
            ),
            'sort'=>array(
                'attributes'=>array(
                    'admin.name'=>array(
                        'asc'=>'admin.name',
                        'desc'=>'admin.name DESC',
                    ),
                    '*',
                ),
                'defaultOrder'=>array(
                    'create_time'=>CSort::SORT_DESC,
                ),
            ),
        ));
    }

    public function scopes()
    {
        $t = $this->tableAlias;

        return array(
            'active'=>array(
                'condition'=>$t.'.unban_time IS NULL AND ('.$t.'.length = 0 OR '.$t.'.create_time + '.$t.'.length * 60 > UNIX_TIMESTAMP())',
            ),
            'expired'=>array(
                'condition'=>$t.'.length > 0 AND '.$t.'.create_time + '.$t.'.length * 60 < UNIX_TIMESTAMP()',
            ),
            'inactive'=>array(
                'condition'=>$t.'.unban_time IS NOT NULL OR ('.$t.'.length > 0 AND '.$t.'.create_time + '.$t.'.length * 60 < UNIX_TIMESTAMP())',
            ),
            'permanent'=>array(
                'condition'=>$t.'.length = 0',
            ),
            'temporary'=>array(
                'condition'=>$t.'.length < 0',
            ),
            'unbanned'=>array(
                'condition'=>$t.'.unban_time IS NOT NULL',
            ),
        );
    }

    public function behaviors()
    {
        return array(
            'CTimestampBehavior' => array(
                'class' => 'zii.behaviors.CTimestampBehavior',
                'updateAttribute' => null,
            ),
        );
    }

    /**
     * @return boolean - whether the record is valid
     */
    private function isValid()
    {
        return $this->steam_account_id
               && ($this->type == self::GAG_TYPE
                   || $this->type == self::MUTE_TYPE
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

    /**
     * Returns whether the ban is active
     * @return boolean whether the ban is active
     */
    public function getIsActive()
    {
        return !$this->unban_time && (!$this->length || $this->create_time + $this->length * 60 > time());
    }

    /**
     * Returns whether the ban is expired
     * @return boolean whether the ban is expired
     */
    public function getIsExpired()
    {
        return $this->length && $this->create_time + $this->length * 60 < time();
    }

    /**
     * Returns whether the ban is permanent
     * @return boolean whether the ban is permanent
     */
    public function getIsPermanent()
    {
        return !$this->length;
    }

    /**
     * Returns whether the ban is temporary
     * @return boolean whether the ban is temporary
     */
    public function getIsTemporary()
    {
        return $this->length < 0;
    }

    /**
     * Returns whether the ban is unbanned
     * @return boolean whether the ban is unbanned
     */
    public function getIsUnbanned()
    {
        return !!$this->unban_time;
    }

    /**
     * Custom setter - converts SteamID to Steam Account ID and saves it in model.
     * @param string $steam - SteamID.
     */
    public function setSteam($steam)
    {
        if ($steam)
            $this->steam_account_id = substr($steam, 8, 1) + 2 * substr($steam, 10, 10);
        else
            $this->steam_account_id = null;
    }

    /**
     * Rerurns the Steam ID (converts it from Steam Account ID)
     * @return string Steam ID
     */
    public function getSteam()
    {
        if (empty($this->steam_account_id)) {
            return null;
        } else {
            $y = $this->steam_account_id % 2;
            $z = ($this->steam_account_id - $y) / 2;

            return 'STEAM_0:' . $y . ':' . $z;
        }
    }

    /**
     * Returns the Steam Community ID
     * @return integer the Steam Community ID
     */
    public function getCommunityId()
    {
        if (empty($this->steam_account_id))
            return null;
        else
            return 0x0110000100000000 + $this->steam_account_id;
    }

    /**
     * Returns the admin name or "CONSOLE" if not set
     * @return string admin name
     */
    public function getAdminName()
    {
        if (isset($this->admin))
            return $this->admin->name;
        else
            return Yii::app()->params["consoleName"];
    }

    /**
     * Returns the unban admin name or "CONSOLE" if not set
     * @return string admin name
     */
    public function getUnbanAdminName()
    {
        if (isset($this->admin))
            return $this->admin->name;
        else
            return Yii::app()->params["consoleName"];
    }

    /**
     * Returns formatted punishment length
     * @return string length
     */
    public function getLengthText()
    {
        if ($this->isPermanent)
            return Yii::t("sourcebans", "Permanent");
        elseif ($this->isTemporary)
            return Yii::t('CommsPlugin.main', 'Temporary');
        else
            return Yii::app()->format->formatLength($this->length * 60);
    }

    /**
     * Returns formatted punishment expired datetime
     * @return string datetime or null
     */
    public function getExpireText()
    {
        if ($this->isPermanent || $this->isTemporary)
            return null;
        else
            return Yii::app()->format->formatDatetime($this->create_time + $this->length * 60);
    }

    /**
     * Returns formatted datetime when punished was removed
     * @return string datetime or null
     */
    public function getUnbanTimeText()
    {
        if ($this->unban_time)
            return Yii::app()->format->formatDatetime($this->unban_time);
        else
            return null;
    }

    /**
     * Returns formatted player steam with name (if present) for log
     * @return string name with steam
     */
    public function getNameForLog()
    {
        if ($this->name)
            return sprintf('"%s" (%s)', $this->name, $this->steam);
        else
            return sprintf('"%s"', $this->steam);
    }

    /**
     * Unbans the communication punishment
     * @param string $reason optional unban reason
     * @return boolean whether the unbanning is successful
     */
    public function unban($reason = null)
    {
        $this->unban_admin_id = Yii::app()->user->id;
        $this->unban_reason   = $reason;
        $this->unban_time     = time();

        return $this->save(false);
    }

    /**
     * This method is invoked before saving a record (after validation, if any).
     */
    protected function beforeSave()
    {
        if($this->isNewRecord && !$this->isInternalRecord) {
            if(!Yii::app()->user->isGuest)
                $this->admin_id = Yii::app()->user->id;

            $this->admin_ip = $_SERVER['REMOTE_ADDR'];
        }

        return parent::beforeSave();
    }
}
