<?php
/* @var $gags Comms */
/* @var $mutes Comms */
/* @var $plugin SourceComms plugin */
/* @var $total_mutes integer Count of mutes in database */
/* @var $total_gags integer Count of gags in database */
?>
<div class="row">
  <section class="mutes span6">
<?php $this->widget('zii.widgets.grid.CGridView', array(
    'id' => 'mutes-grid',
    'dataProvider' => $mutes,
    'columns' => array(
        array(
            'header' => Yii::t('sourcebans', 'Game'),
            'headerHtmlOptions' => array(
                'class' => 'icon',
            ),
            'htmlOptions' => array(
                'class' => 'icon',
            ),
            'name' => 'server.game.name',
            'type' => 'html',
            'value' => 'CHtml::image(Yii::app()->baseUrl . "/images/games/" . (isset($data->server) ? $data->server->game->icon : "web.png"), isset($data->server) ? $data->server->game->name : "SourceBans")',
        ),
        array(
            'headerHtmlOptions' => array(
                'class' => 'datetime ',
            ),
            'htmlOptions' => array(
                'class' => 'datetime',
            ),
            'name' => 'create_time',
            'type' => 'datetime',
        ),
        'name',
        array(
            'headerHtmlOptions' => array(
                'class' => 'length',
            ),
            'htmlOptions' => array(
                'class' => 'length',
            ),
            'name' => 'length',
            'value' => '$data->lengthText',
        ),
    ),
    'cssFile' => false,
    'enablePagination' => false,
    'enableSorting' => false,
    'itemsCssClass' => 'items table table-condensed table-hover',
    'nullDisplay' => CHtml::tag('span', array('class' => 'null'), Yii::t('zii', 'Not set')),
    'rowHtmlOptionsExpression' => 'array(
        "class" => ($data->isExpired ? "expired" : ($data->isUnbanned ? "unbanned" : "")),
        "data-key" => $data->primaryKey,
    )',
    'selectionChanged' => 'js:function(grid) {
        var $header = $("#" + grid + " tr.selected");
        var id      = $header.data("key");

        location.href = "' . $this->createUrl('comms/index', array('#' => '__ID__')) . '".replace("__ID__", id);
    }',
    'summaryText' => '<div style="float: left">'
                    . CHtml::image(Comms::getIcon(Comms::TYPE_MUTE, CHtml::asset($plugin->getPath('assets'))), Comms::getType(Comms::TYPE_MUTE))
                    . '&nbsp;<b><u>' . Yii::t('CommsPlugin.main', 'Last mutes') . '</u></b>'
                    . '</div><div style="float: right"><em>' . Yii::t('CommsPlugin.main', 'Total') . ': ' . $total_mutes . '</em></div>',
)) ?><!-- mutes grid -->
  </section>

  <section class="gags span6">
<?php $this->widget('zii.widgets.grid.CGridView', array(
    'id' => 'gags-grid',
    'dataProvider' => $gags,
    'columns' => array(
        array(
            'header' => Yii::t('sourcebans', 'Game'),
            'headerHtmlOptions' => array(
                'class' => 'icon',
            ),
            'htmlOptions' => array(
                'class' => 'icon',
            ),
            'name' => 'server.game.name',
            'type' => 'html',
            'value' => 'CHtml::image(Yii::app()->baseUrl . "/images/games/" . (isset($data->server) ? $data->server->game->icon : "web.png"), isset($data->server) ? $data->server->game->name : "SourceBans")',
        ),
        array(
            'headerHtmlOptions' => array(
                'class' => 'datetime ',
            ),
            'htmlOptions' => array(
                'class' => 'datetime',
            ),
            'name' => 'create_time',
            'type' => 'datetime',
        ),
        'name',
        array(
            'headerHtmlOptions' => array(
                'class' => 'length',
            ),
            'htmlOptions' => array(
                'class' => 'length',
            ),
            'name' => 'length',
            'value' => '$data->lengthText',
        ),
    ),
    'cssFile' => false,
    'enablePagination' => false,
    'enableSorting' => false,
    'itemsCssClass' => 'items table table-condensed table-hover',
    'nullDisplay' => CHtml::tag('span', array('class' => 'null'), Yii::t('zii', 'Not set')),
    'rowHtmlOptionsExpression' => 'array(
        "class" => ($data->isExpired ? "expired" : ($data->isUnbanned ? "unbanned" : "")),
        "data-key" => $data->primaryKey,
    )',
    'selectionChanged' => 'js:function(grid) {
        var $header = $("#" + grid + " tr.selected");
        var id      = $header.data("key");

        location.href = "' . $this->createUrl('comms/index', array('#' => '__ID__')) . '".replace("__ID__", id);
    }',
    'summaryText' => '<div style="float: left">'
                    . CHtml::image(Comms::getIcon(Comms::TYPE_GAG, CHtml::asset($plugin->getPath('assets'))), Comms::getType(Comms::TYPE_GAG))
                    . '&nbsp;<b><u>' . Yii::t('CommsPlugin.main', 'Last gags') . '</u></b>'
                    . '</div><div style="float: right"><em>' . Yii::t('CommsPlugin.main', 'Total') . ': ' . $total_gags . '</em></div>',
)) ?><!-- gags grid -->
  </section>
</div>
