<?php

/**
 * This is the model class for table "{{comms}}".
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
     * Returns the static model of the specified AR class.
     * @param string $className active record class name.
     * @return Comms the static model class
     */
    public static function model($className=__CLASS__)
    {
        return parent::model($className);
    }

    /**
     * @return string the associated database table name
     */
    public function tableName()
    {
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
            array('type, reason, length', 'required'),
            array('type, length', 'numerical', 'integerOnly'=>true),
            array('steam', 'match', 'pattern'=>SourceBans::STEAM_PATTERN),
            array('name', 'length', 'max'=>64),
            array('reason, unban_reason', 'length', 'max'=>255),
            // The following rule is used by search().
            // Please remove those attributes that should not be searched.
            array('id, type, steam_account_id, name, reason, length, server_id, admin_id, admin_ip, unban_admin_id, unban_reason, unban_time, create_time', 'safe', 'on'=>'search'),
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
    public function search()
    {
        // Warning: Please modify the following code to remove attributes that
        // should not be searched.

        $criteria=new CDbCriteria;
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
     * Returns whether the ban is active
     *
     * @return boolean whether the ban is active
     */
    public function getIsActive()
    {
        return !$this->unban_time && (!$this->length || $this->create_time + $this->length * 60 > time());
    }

    /**
     * Returns whether the ban is expired
     *
     * @return boolean whether the ban is expired
     */
    public function getIsExpired()
    {
        return $this->length && $this->create_time + $this->length * 60 < time();
    }

    /**
     * Returns whether the ban is permanent
     *
     * @return boolean whether the ban is permanent
     */
    public function getIsPermanent()
    {
        return !$this->length;
    }

    /**
     * Returns whether the ban is temporary
     *
     * @return boolean whether the ban is temporary
     */
    public function getIsTemporary()
    {
        return $this->length < 0;
    }

    /**
     * Returns whether the ban is unbanned
     *
     * @return boolean whether the ban is unbanned
     */
    public function getIsUnbanned()
    {
        return !!$this->unban_time;
    }



    /**
     * Returns the supported ban types
     *
     * @return array the supported ban types
     */
    public static function getTypes()
    {
        return array(
            self::GAG_TYPE  => Yii::t('CommsPlugin.main', 'Gag'),
            self::MUTE_TYPE => Yii::t('CommsPlugin.main', 'Mute'),
        );
    }

    /**
     * Custom setter - converts SteamID to Steam Account ID and saves it in model.
     * @param string $steam - SteamID.
     *
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
     *
     * @return string Steam ID
     */
    public function getSteam()
    {
        if (empty($this->steam_account_id))
        {
            return null;
        }
        else
        {
            $y = $this->steam_account_id % 2;
            $z = ($this->steam_account_id - $y) / 2;

            return 'STEAM_0:' . $y . ':' . $z;
        }
    }

    /**
     * Returns the Steam Community ID
     *
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
     *
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
     * Returns formatted punishment length
     *
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
     *
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
     * Unbans the ban
     *
     * @param string $reason optional unban reason
     * @return boolean whether the unbanning is successful
     */
    // public function unban($reason = null)
    // {
    //     $this->unban_admin_id = Yii::app()->user->id;
    //     $this->unban_reason   = $reason;
    //     $this->unban_time     = time();

    //     return $this->save(false);
    // }


    protected function beforeSave()
    {
        if($this->isNewRecord)
        {
            if(!Yii::app()->user->isGuest)
            {
                $this->admin_id = Yii::app()->user->id;
            }

            $this->admin_ip = $_SERVER['SERVER_ADDR'];
        }
        if(!empty($this->steam))
        {
            $this->steam = strtoupper($this->steam);
        }

        return parent::beforeSave();
    }
}
