<?php
/* @var $this CommsController */
/* @var $plugin CommsPlugin */
/* @var $comms Comms */
?>

<section>
  <div class="container" style="margin-bottom: 1em; width: 500px;">
    <?php echo CHtml::link(Yii::t('sourcebans', 'Advanced search'),'#',array('class'=>'search-button', 'style'=>'margin-left: 180px')); ?>
    <div class="search-form" style="display:none">
      <?php $this->renderPartial($plugin->getViewFile('_search'),array(
          'model'=>$comms,
      )); ?>
    </div><!-- search-form -->
  </div>

<?php $grid=$this->widget('zii.widgets.grid.CGridView', array(
    'id'=>'comms-grid',
    'dataProvider'=>$comms->search(),
    'columns'=>array(
        array(
            'class'=>'CCheckBoxColumn',
            'selectableRows'=>2,
            'visible'=>!Yii::app()->user->isGuest && Yii::app()->user->data->hasPermission('DELETE_COMMS'),
        ),
        array(
            'header'=>Yii::t('sourcebans', 'Game') . '/' . Yii::t('sourcebans', 'Type'),
            'headerHtmlOptions'=>array(
                'class'=>'icon',
            ),
            'htmlOptions'=>array(
                'class'=>'icon',
            ),
            'type'=>'html',
            'value'=>'CHtml::image(Yii::app()->baseUrl . "/images/games/" . (isset($data->server) ? $data->server->game->icon : "web.png"), isset($data->server) ? $data->server->game->name : "SourceBans") . "&nbsp;" . ' .
                'CHtml::image("' . CHtml::asset($plugin->getPath('assets')) . '/images/type_" . ($data->type == Comms::GAG_TYPE ? "c" : "v") . ".png", ($types = Comms::getTypes()) ? $types[$data->type] : null)',
        ),
        array(
            'headerHtmlOptions'=>array(
                'class'=>'datetime',
            ),
            'htmlOptions'=>array(
                'class'=>'datetime',
            ),
            'name'=>'create_time',
            'type'=>'datetime',
        ),
        'name',
        array(
            'header'=>Yii::t('sourcebans', 'Admin'),
            'headerHtmlOptions'=>array(
                'class'=>'SBAdmin_name span3',
            ),
            'htmlOptions'=>array(
                'class'=>'SBAdmin_name span3',
            ),
            'name'=>'admin.name',
            'value'=>'isset($data->admin) ? $data->admin->name :  Yii::app()->params["consoleName"]',
            'visible'=>!(Yii::app()->user->isGuest && SourceBans::app()->settings->bans_hide_admin),
        ),
        array(
            'headerHtmlOptions'=>array(
                'class'=>'length',
            ),
            'htmlOptions'=>array(
                'class'=>'length',
            ),
            'name'=>'length',
            'value'=>'$data->isPermanent ? Yii::t("sourcebans", "Permanent") : Yii::app()->format->formatLength($data->length*60)',
        ),
    ),
    'cssFile'=>false,
    'itemsCssClass'=>'items table table-accordion table-condensed table-hover',
    'nullDisplay'=>CHtml::tag('span', array('class'=>'null'), Yii::t('zii', 'Not set')),
    'pager'=>array(
        'class'=>'bootstrap.widgets.TbPager',
    ),
    'rowHtmlOptionsExpression'=>'array(
        "class"=>"header" . ($data->isExpired ? " expired" : ($data->isUnbanned ? " unbanned" : "")),
    )',
    'pagerCssClass'=>'pagination pagination-right',
    'selectableRows'=>0,
)) ?><!-- comms grid -->

</section>

<?php Yii::app()->clientScript->registerScript('search', "
  $('.search-button').click(function(){
      $('.search-form').slideToggle();
      return false;
  });
  $('.search-form form').submit(function(){
      $('#comms-grid').yiiGridView('update', {
          data: $(this).serialize()
      });
      return false;
  });
"); ?>

<?php Yii::app()->clientScript->registerScript('site_bans_queryServer', '
  $.getJSON("' . $this->createUrl('servers/info') . '", function(servers) {
    $.each(servers, function(i, server) {
      $("#Comms_server_id option[value=\"" + server.id + "\"]").html(server.error ? server.error.message : server.hostname);
    });
  });
') ?>
