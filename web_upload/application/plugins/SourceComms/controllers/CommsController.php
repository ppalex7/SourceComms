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
                'actions'=>array('admin'),
                'expression'=>'!Yii::app()->user->isGuest && Yii::app()->user->data->hasPermission("ADD_COMMS", "IMPORT_COMMS")',
            ),
            array('allow',
                'actions'=>array('add'),
                'expression'=>'!Yii::app()->user->isGuest && Yii::app()->user->data->hasPermission("ADD_COMMS")',
            ),
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

    /**
     * Displays the 'Comms' admin page
     */
    public function actionAdmin()
    {
        $this->_loadPlugin();

        $this->layout = '//layouts/column2';

        $this->pageTitle = Yii::t('CommsPlugin.main', 'Comms');

        $this->breadcrumbs = array(
            Yii::t('sourcebans', 'controllers.admin.index.title') => array('admin/index'),
            $this->pageTitle,
        );

        $this->menu = array(
            array(
                'label' => Yii::t('CommsPlugin.main', 'Add punishment'),
                'url' => '#add',
                'visible' => Yii::app()->user->data->hasPermission('ADD_COMMS')
            ),
            // array(
            //     'label' => Yii::t('CommsPlugin.main', 'Import punishments'),
            //     'url' => '#import',
            //     'visible' => Yii::app()->user->data->hasPermission('IMPORT_COMMS')
            // ),
        );

        $comms = new Comms;
        $comms->unsetAttributes();  // clear any default values

        $this->render($this->_plugin->getViewFile('admin'),array(
            'comms' => $comms,
            'plugin' => $this->_plugin,
        ));
    }

    /**
     * Creates a new model.
     * If creation is successful, the browser will be redirected to the 'view' page.
     */
    public function actionAdd()
    {
        $this->_loadPlugin();
        $model = new Comms;

        // Uncomment the following line if AJAX validation is needed
        $this->performAjaxValidation($model);

        if(isset($_POST['Comms']))
        {
            $model->attributes=$_POST['Comms'];
            if($model->save())
            {
                switch ($model->type)
                {
                    case Comms::GAG_TYPE:
                        SourceBans::log('Gag added', 'Gag against ' . $model->nameForLog . ' was added');
                        break;
                    case Comms::MUTE_TYPE:
                        SourceBans::log('Mute added', 'Mute against ' . $model->nameForLog . ' was added');
                        break;
                    default:
                        SourceBans::log('Communication punishment added', 'Communication punshment against ' . $model->nameForLog . ' was added');
                        break;
                }
                Yii::app()->user->setFlash('success', Yii::t('sourcebans', 'Saved successfully'));

                $this->redirect(array('site/comms','#'=>$model->id));
            }
        }
    }

    /**
     * Performs the AJAX validation.
     * @param Comms $model the model to be validated
     */
    protected function performAjaxValidation($model)
    {
        if(isset($_POST['ajax']) && $_POST['ajax']==='comms-form')
        {
            echo CActiveForm::validate($model);
            Yii::app()->end();
        }
    }
}
