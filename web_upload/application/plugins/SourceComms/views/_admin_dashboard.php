<?php
/* @var $total_mutes Count of mutes in database */
/* @var $total_gags Count of gags in database */
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
