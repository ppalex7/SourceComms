<?php
/* @var $total_mutes integer Count of mutes in database */
/* @var $total_gags integer Count of gags in database */
?>

<tr>
    <td class="value" width="20%">
        <?php echo $total_mutes ?>
    </td>
    <td width="30%">
        <?php echo Yii::t('CommsPlugin.main', 'Mutes count', $total_mutes) ?>
    </td>
    <td class="value" width="20%">
        <?php echo $total_gags ?>
    </td>
    <td width="30%">
        <?php echo Yii::t('CommsPlugin.main', 'Gags count', $total_gags) ?>
    </td>
</tr>
