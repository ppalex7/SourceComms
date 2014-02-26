<?php
/**
 * CommsSettingsForm is the data structure for the SourceComms plugin settings.
 * It is used by the 'settings' action of 'PluginsController'.
 *
 * @author Alex
 * @copyright (C)2013-2014 Alexandr Duplishchev.
 * @link https://github.com/d-ai/SourceComms
 *
 */
class CommsSettingsForm extends CFormModel
{
    private $_data = array();

    /**
     * @var array with default plugin settings
     */
    public static $defaultSettings = array(
       #'sourcebans__max__settings_length'
        'sourcecomms_show_on_dashboard'     => 1,
        'sourcecomms_use_immunity'          => 0,
    );

    public function __get($name)
    {
        if(isset($this->_data[$name]))
            return $this->_data[$name];

        return parent::__get($name);
    }

    public function __set($name, $value)
    {
        if(isset($this->_data[$name]))
            return $this->_data[$name] = $value;

        parent::__set($name, $value);
    }


    public function init()
    {
        $this->_data = CHtml::listData(SBSetting::model()->findAllByPk(array_keys(self::$defaultSettings)),  'name', 'value');
    }

    /**
     * @return array validation rules for model attributes.
     */
    public function rules()
    {
        return array(
            array('sourcecomms_show_on_dashboard, sourcecomms_use_immunity', 'boolean'),
        );
    }

    /**
     * @return array customized attribute labels (name=>label)
     */
    public function attributeLabels()
    {
        return array(
            'sourcecomms_show_on_dashboard' => Yii::t('CommsPlugin.settings', 'Show last punishments on the site dashboard.'),
            'sourcecomms_use_immunity'      => Yii::t('CommsPlugin.settings', "Use administrators' immunity during checking rights."),
        );
    }

    /**
     * Saves the sourcecomms settings using the given values in the model.
     * @return boolean whether save is successful
     */
    public function save()
    {
        $settings = SBSetting::model()->findAllByPk(array_keys(self::$defaultSettings), array('index' => 'name'));

        foreach ($this->_data as $name => $value){
            if (SourceBans::app()->settings->$name != $value) {
                $settings[$name]->value = trim($value);
                $settings[$name]->save();
            }
        }

        return true;
    }
}

