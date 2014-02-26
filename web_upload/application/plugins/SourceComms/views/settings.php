<?php
/* @var $this PluginsController */
/* @var $settings CommsSettingsForm */
/* @var $form CActiveForm */
?>

<?php $form=$this->beginWidget('CActiveForm', array(
    'id'=>'comms-settings-form',
    'enableAjaxValidation'=>true,
    'enableClientValidation'=>true,
    'clientOptions'=>array(
        'inputContainer'=>'.control-group',
        'validateOnSubmit'=>true,
    ),
    'errorMessageCssClass'=>'help-inline',
    'htmlOptions'=>array(
        'class'=>'form-horizontal',
    ),
)) ?>

<fieldset>
  <legend><?php echo Yii::t('sourcebans', 'General') ?></legend>

  <div class="control-group">
    <div class="controls">
      <?php $checkbox = $form->checkBox($settings, 'sourcecomms_use_immunity') . $settings->getAttributeLabel('sourcecomms_use_immunity'); ?>
      <?php echo CHtml::label($checkbox, 'CommsSettingsForm_use_immunity', array('class' => 'checkbox')); ?>
    </div>
  </div>

</fieldset>

<fieldset>
  <legend><?php echo Yii::t('CommsPlugin.main', 'Interface') ?></legend>
  <div class="control-group">
    <div class="controls">
      <?php $checkbox = $form->checkBox($settings, 'sourcecomms_show_on_dashboard') . $settings->getAttributeLabel('sourcecomms_show_on_dashboard'); ?>
      <?php echo CHtml::label($checkbox, 'CommsSettingsForm_show_on_dashboard', array('class' => 'checkbox')); ?>
    </div>
  </div>
</fieldset>

  <div class="control-group buttons">
    <div class="controls">
      <?php echo CHtml::submitButton(Yii::t('sourcebans', 'Save'), array('class' => 'btn')); ?>
    </div>
  </div>

<?php $this->endWidget() ?>
