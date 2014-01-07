<?php
/**
 * SourceComms controller
 *
 * @author Alex
 * @copyright (C)2013-2014 Alexandr Duplishchev.
 * @link https://github.com/d-ai/SourceComms
 *
 * @package sourcecomms.controllers
 * @since 1.0
 */
class CommsController extends Controller
{
    /**
     * @var SBPlugin - SourceComms plugin model.
     */
    private $_plugin;

    /**
     * @var string - assets URL for SourceComms plugin.
     */
    private $_assetsUrl;

    /**
     * Does common actions before doing anyting
     */
    private function _loadPlugin()
    {
        // Load plugin info
        $this->_plugin = SBPlugin::model()->findById('SourceComms');

        // Import plugin models
        Yii::import($this->_plugin->getPathAlias('models.*'));

        // Get and register assets path
        $this->_assetsUrl = Yii::app()->assetManager->publish($this->_plugin->getPath('assets'));

        // Register custom css file
        Yii::app()->clientScript->registerCssFile($this->_assetsUrl . '/css/sourcecomms.css');
    }

    /**
     * @return array action filters
     */
    public function filters()
    {
        return array(
            'accessControl', // perform access control for CRUD operations
        );
    }

    /**
     * Specifies the access control rules.
     * This method is used by the 'accessControl' filter.
     * @return array access control rules
     */
    public function accessRules()
    {
        return array(
            array('allow',
                'actions'=>array('index'),
            ),
            array('deny',  // deny all users
                'users'=>array('*'),
            ),
        );
    }

    /**
     * Displays the 'Comms' list page
     */
    public function actionIndex()
    {
        $this->_loadPlugin();

        $this->pageTitle=Yii::t('CommsPlugin.main', 'Comms');

        $this->breadcrumbs=array(
            $this->pageTitle,
        );

        $comms = new Comms('search');
        $comms->unsetAttributes();  // clear any default values
        if(isset($_GET['Comms']))
            $comms->attributes=$_GET['Comms'];

        $comment = new SBComment;
        $comment->object_type = Comms::COMMENTS_TYPE;

        $this->render($this->_plugin->getViewFile('index'), array(
            'comms' => $comms,
            'plugin' => $this->_plugin,
            'comment' => $comment,
        ));
    }
}
