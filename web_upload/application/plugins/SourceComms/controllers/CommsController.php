<?php
class CommsController extends Controller
{
    public function actionIndex()
    {
        $this->pageTitle=Yii::t('CommsPlugin.main', 'Comms');

        $this->breadcrumbs=array(
            $this->pageTitle,
        );

        $plugin = SBPlugin::model()->findById('SourceComms');

        Yii::import($plugin->getPathAlias('models.*'));

        $comms = new Comms('search');
        $comms->unsetAttributes();  // clear any default values
        if(isset($_GET['Comms']))
            $comms->attributes=$_GET['Comms'];

        $this->render($plugin->getViewFile('index'), array(
            'comms' => $comms,
            'plugin' => $plugin,
        ));
    }
}
