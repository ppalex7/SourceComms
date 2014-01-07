<?php
/* @var $this CommsController */
/* @var $plugin CommsPlugin */
/* @var $comms Comms */
?>

<?php if(Yii::app()->user->data->hasPermission('ADD_COMMS')): ?>
    <section class="tab-pane fade" id="pane-add">
<?php echo $this->renderPartial($plugin->getViewFile('_form'), array(
    'action'=>array('comms/add'),
    'model'=>$comms,
)) ?>

    </section>
<?php endif ?>

<?php if(Yii::app()->user->data->hasPermission('IMPORT_COMMS')): ?>
    <section class="tab-pane fade" id="pane-import">
<?php echo $this->renderPartial($plugin->getViewFile('_import')) ?>

    </section>
<?php endif ?>
