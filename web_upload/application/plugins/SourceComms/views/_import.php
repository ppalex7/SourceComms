<?php
/* @var $this CommsController */
/* @var $tables CArrayDataProvider of tables available for import */
?>

<!-- there will be info about existing tables and buttons to import data -->
<?php $this->widget('bootstrap.widgets.TbProgress', array(
    'type' => 'success',
    'percent' => 0,
    'striped' => true,
    'htmlOptions' => array(
        'id' => 'importProgress',
        'style' => "display: none;",
    ))
); ?>

<?php
$this->widget('zii.widgets.grid.CGridView', array(
    'id'=>'tables-grid',
    'dataProvider'=>$tables,
    'columns'=>array(
        array(
            'header' => Yii::t('CommsPlugin.main', 'Table name'),
            'value'  => '$data["tableName"]',
            'htmlOptions' => array(
                'style' => 'width: 50%',
            ),
        ),
        array(
            'header' => Yii::t('CommsPlugin.main', 'Added'),
            'value'  => '0',
            'htmlOptions' => array(
                'class' => 'text-center added',
            ),
            'headerHtmlOptions' => array(
                'class' => 'text-center',
            ),
        ),
        array(
            'header' => Yii::t('CommsPlugin.main', 'Skipped'),
            'value'  => '0',
            'htmlOptions' => array(
                'class' => 'text-center skipped',
            ),
            'headerHtmlOptions' => array(
                'class' => 'text-center',
            ),
        ),
        array(
            'header' => Yii::t('CommsPlugin.main', 'Total records'),
            'value'  => '"?"',
            'htmlOptions' => array(
                'class' => 'text-center total',
            ),
            'headerHtmlOptions' => array(
                'class' => 'text-center',
            ),
        ),
        array(
            'class'=>'CButtonColumn',
            'buttons'=>array(
                'import' => array(
                    'label'     => Yii::t('CommsPlugin.main', 'Import'),
                    'imageUrl'  => false,
                    'click'   => 'function () {
                        if ($(this).hasClass("disabled")) {
                            return false;
                        }
                        $(".btn.import").addClass("disabled");
                        importIteration($(this).parents("tr").data("key"), 0);
                    }',
                    'options' => array(
                        'class' => 'btn btn-default btn-xs import',
                        'role' => 'button',
                    ),
                ),
            ),
            'template'=>'{import}',
        ),
    ),
    'cssFile'=>false,
    'itemsCssClass'=>'items table table-accordion table-bordered table-condensed table-hover',
    'rowHtmlOptionsExpression'=>'array(
        "data-key"=>$data["tableName"],
    )',
    'summaryCssClass'=>'',
    'summaryText'=>false,
))
?>

<?php Yii::app()->clientScript->registerScript('import','
    function unlockButtons() {
        $(".btn.import").each(
            function () {
                if (!($(this).hasClass("completed") || $(this).hasClass("error"))) {
                    $(this).removeClass("disabled");
                }
            }
        );
    };

    function importIteration (table, offset) {
        var progress = $("#importProgress");
        var progressBar = progress.children(".bar");

        progress.show();
        if (!offset) {
            progressBar.width(1);
        }
        progress.addClass("active");

        $.ajax({
            type: "POST",
            url: "' . Yii::app()->createUrl('comms/import') . '",
            data: {
                offset: offset,
                table:  table,
            },
            dataType: "json",
            timeout: 300000
        }).done(
            function (result) {
                var row = $("#tables-grid tr[data-key=\"" + table + "\"]");
                switch (result.status) {
                    case "process":
                        row.children(".added").html(result.added + parseInt(row.children(".added").html()));
                        row.children(".skipped").html(result.skipped + parseInt(row.children(".skipped").html()));
                        row.children(".total").html(result.total);
                        progressBar.width(parseInt(result.offset * progress.width() / result.total) + 1);
                        setTimeout(
                            function () { importIteration(table, result.offset); },
                            100
                        );
                        break;

                    case "finish":
                        row.find(".btn.import").addClass("completed");
                        unlockButtons();
                        progress.removeClass("active");
                        $.alert("' . Yii::t('CommsPlugin.main', 'Import completed') . '", "success");
                        break;

                    case "error":
                        row.find(".btn.import").addClass("error");
                        unlockButtons();
                        progress.hide();
                        $.alert("' . Yii::t('CommsPlugin.main', 'An error was occurred, code: {code}') . '".replace("{code}", result.code), "error");
                        break;
                }
            }
        ).fail(
            function () {
                unlockButtons();
                progress.hide();
                $.alert("' . Yii::t('CommsPlugin.main', 'An error was occurred, code: {code}', array('code' => 104)) . '", "error");
            }
        );
    };
'); ?>

