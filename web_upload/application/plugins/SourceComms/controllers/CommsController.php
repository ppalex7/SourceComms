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
    const ITEMS_PER_ITERATION = 50;
    const POSSIBLE_TABLE_NAMES = '/(?:comms|^old_comms_\d+|^extendedcomm)$/i';

    /**
     * @var array of model names which is available for import
     */
    protected static $availableModels = array(
        'OldComms',
        'ExtendedComm',
        'CommsForImport',
    );

    /**
     * @var SBPlugin - SourceComms plugin model.
     */
    private $_plugin;

    /**
     * Does common actions before doing anyting
     */
    public function init()
    {
        // Load plugin info
        $this->_plugin = SBPlugin::model()->findById('SourceComms');
    }

    /**
     * @return array action filters
     */
    public function filters()
    {
        return array(
            'accessControl', // perform access control for CRUD operations
            'postOnly + add, unban, import, delete', // we only allow deletion via POST request
            'ajaxOnly + import',
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
                'actions' => array('admin'),
                'expression' => '!Yii::app()->user->isGuest && Yii::app()->user->data->hasPermission("ADD_COMMS", "OWNER")',
            ),
            array('allow',
                'actions' => array('add'),
                'expression' => '!Yii::app()->user->isGuest && Yii::app()->user->data->hasPermission("ADD_COMMS")',
            ),
            array('allow',
                'actions' => array('unban'),
                'expression' => '!Yii::app()->user->isGuest && Yii::app()->user->data->hasPermission("UNBAN_ALL_BANS", "UNBAN_GROUP_BANS", "UNBAN_OWN_BANS")',
            ),
            array('allow',
                'actions'=>array('delete'),
                'expression'=>'!Yii::app()->user->isGuest && Yii::app()->user->data->hasPermission("DELETE_COMMS")',
            ),
            array('allow',
                'actions' => array('import'),
                'expression' => '!Yii::app()->user->isGuest && Yii::app()->user->data->hasPermission("OWNER")',
            ),
            array('allow',
                'actions' => array('index'),
            ),
            array('allow',
                'actions' => array('test'),
            ),
            array('deny',  // deny all users
                'users' => array('*'),
            ),
        );
    }

    /**
     * Displays the 'Comms' list page
     */
    public function actionIndex()
    {
        $this->pageTitle = Yii::t('CommsPlugin.main', 'Comms');

        $this->breadcrumbs = array(
            $this->pageTitle,
        );

        $hideInactive = Yii::app()->request->getQuery('hideinactive', 'false') == 'true';

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
            'hideInactive' => $hideInactive,
            'total_punishments' => $comms->count(array(
                'scopes' => $hideInactive ? 'active' : null,
            )),
        ));
    }

    /**
     * Displays the 'Comms' admin page
     */
    public function actionAdmin()
    {
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
            array(
                'label' => Yii::t('CommsPlugin.main', 'Import punishments'),
                'url' => '#import',
                'visible' => Yii::app()->user->data->hasPermission('OWNER')
            ),
        );

        $comms = new Comms;
        $comms->unsetAttributes();  // clear any default values

        // Get available tables for importing
        $tables = array();
        if (Yii::app()->user->data->hasPermission("OWNER"))
        {
            foreach (Yii::app()->db->getSchema()->getTableNames() as $tableName) {
                if (preg_match(self::POSSIBLE_TABLE_NAMES, $tableName)
                    && $tableName != $comms->getTableSchema()->name
                ) {
                    $tables[] = array('tableName' => $tableName);
                }
            }
        }
        $gridDataProvider = new CArrayDataProvider($tables);
        $gridDataProvider->pagination = false;

        $this->render($this->_plugin->getViewFile('admin'),array(
            'comms' => $comms,
            'plugin' => $this->_plugin,
            'tables' => $gridDataProvider,
        ));
    }

    /**
     * Creates a new model.
     * If creation is successful, the browser will be redirected to the 'view' page.
     */
    public function actionAdd()
    {
        $model = new Comms;

        // Uncomment the following line if AJAX validation is needed
        $this->performAjaxValidation($model);

        if(isset($_POST['Comms'])) {
            $model->attributes = $_POST['Comms'];

            if($model->save()) {
                switch ($model->type) {
                    case Comms::GAG_TYPE:
                        SourceBans::log('Gag added', 'Gag against ' . $model->nameForLog . ' was added', SBLog::TYPE_INFORMATION);
                        break;
                    case Comms::MUTE_TYPE:
                        SourceBans::log('Mute added', 'Mute against ' . $model->nameForLog . ' was added', SBLog::TYPE_INFORMATION);
                        break;
                    default:
                        SourceBans::log('Communication punishment added', 'Communication punshment against ' . $model->nameForLog . ' was added', SBLog::TYPE_INFORMATION);
                        break;
                }

                Yii::app()->user->setFlash('success', Yii::t('sourcebans', 'Saved successfully'));

                $this->redirect(array('site/comms','#'=>$model->id));
            }
        }
    }

    /**
     * Unbans a particular model.
     * @param integer $id the ID of the model to be unbanned
     * @throws CHttpException
     */
    public function actionUnban($id)
    {
        $reason = Yii::app()->request->getPost('reason');
        $model = $this->loadModel($id);

        if(!$this->canUpdate('UNBAN', $model))
            throw new CHttpException(403, Yii::t('yii', 'You are not authorized to perform this action.'));

        $unbanned = $model->unban($reason);
        if ($unbanned) {
            switch ($model->type) {
                case Comms::GAG_TYPE:
                    SourceBans::log('Player ungagged', 'Player ' . $model->nameForLog . ' has been ungagged', SBLog::TYPE_INFORMATION);
                    break;
                case Comms::MUTE_TYPE:
                    SourceBans::log('Player unmuted', 'Player ' . $model->nameForLog . ' has been unmuted', SBLog::TYPE_INFORMATION);
                    break;
                default:
                    SourceBans::log('Communication punishment unbanned', 'Communication punshment against ' . $model->nameForLog . ' was unbanned', SBLog::TYPE_INFORMATION);
                    break;
            }
        }

        Yii::app()->end($unbanned);
    }

    /**
     * Deletes a particular model.
     * If deletion is successful, the browser will be redirected to the 'admin' page.
     * @param integer $id the ID of the model to be deleted
     */
    public function actionDelete($id)
    {
        $model=$this->loadModel($id);
        if ($model->delete()) {
            switch ($model->type) {
                case Comms::GAG_TYPE:
                    SourceBans::log('Gag deleted', 'Gag against ' . $model->nameForLog . ' was deleted', SBLog::TYPE_WARNING);
                    break;
                case Comms::MUTE_TYPE:
                    SourceBans::log('Mute deleted', 'Mute against ' . $model->nameForLog . ' was deleted', SBLog::TYPE_WARNING);
                    break;
                default:
                    SourceBans::log('Communication punishment deleted', 'Communication punshment against ' . $model->nameForLog . ' was deleted', SBLog::TYPE_WARNING);
                    break;
            }
        }

        // if AJAX request (triggered by deletion via admin grid view), we should not redirect the browser
        if(!isset($_GET['ajax']))
            $this->redirect(isset($_POST['returnUrl']) ? $_POST['returnUrl'] : array('admin'));
    }

    public function actionImport()
    {

        $tableName  = Yii::app()->request->getParam('table');
        $offset     = Yii::app()->request->getParam('offset');

        if (!$tableName || $offset === null || $offset < 0) {
            Yii::log('Sourcecomms error 102: No table name or offset specified');
            echo CJSON::encode(array('status' => 'error', 'code' => 102));
            Yii::app()->end();
        }

        $modelName;
        foreach (self::$availableModels as $curModelName) {
            if ($curModelName::isTableValidForModel($tableName)) {
                $modelName = $curModelName;
                break;
            }
        }

        // No valid model
        if (!$modelName) {
            Yii::log('Sourcecomms error 103: No valid model for specified table');
            echo CJSON::encode(array('status' => 'error', 'code' => 103));
            Yii::app()->end();
        }

        // Clearing schema cache at start
        if ($offset === 0) {
            Yii::app()->db->schema->getTables();
            Yii::app()->db->schema->refresh();
        }

        $model = new $modelName('search', $tableName);
        $totalCount = $model->count();
        if ($offset >= $totalCount) {
            echo CJSON::encode(array('status' => 'finish', 'table' => $tableName));
            Yii::app()->end();
        }

        $criteria = new CDbCriteria();
        $criteria->offset = $offset;
        $criteria->limit = self::ITEMS_PER_ITERATION;
        $data = $model->with($modelName::$availableRelations)->FindAll($criteria);

        if (!$data) {
            // something strange was happened
            echo CJSON::encode(array('status' => 'finish'));
            Yii::app()->end();
        }

        $added = 0;
        $skipped = 0;
        foreach ($data as $record) {
            foreach ($record->getDataForImport() as $possibleRecord) {
                if ($possibleRecord['search'] === null) {
                    $skipped++;
                    continue;
                }

                $comms = new Comms();
                if ($comms->findByAttributes($possibleRecord['search']) === null) {
                    if ($possibleRecord['save'] === null) {
                        $skipped++;
                        continue;
                    }
                    $comms->setAttributes($possibleRecord['save'], false);
                    $comms->detachBehaviors();
                    if ($comms->save())
                        $added++;
                    else
                        $skipped++;
                } else {
                    $skipped++;
                }
            }
        }
        echo CJSON::encode(array(
            'status'    => 'process',
            'added'     => $added,
            'skipped'   => $skipped,
            'offset'    => $offset + self::ITEMS_PER_ITERATION,
            'total'     => +$totalCount,
            'table'     => $tableName,
        ));
    }

    /**
     * Checks admin permmisions for action
     * @param string $type type of action to check permissions
     * @param Comms $model - model to permissions check
     * @return boolean check result
     */
    public function canUpdate($type, $model)
    {
        if(Yii::app()->user->data->hasPermission($type . '_ALL_COMMS'))
            return true;

        if(Yii::app()->user->data->hasPermission($type . '_GROUP_COMMS') && isset($model->admin)) {
            $groups = CHtml::listData($model->admin->server_groups, 'id', 'name');
            if(Yii::app()->user->data->hasGroup($groups))
                return true;
        }

        return Yii::app()->user->data->hasPermission($type . '_OWN_COMMS') && Yii::app()->user->id == $model->admin_id;
    }

    /**
     * Returns the data model based on the primary key given in the GET variable.
     * If the data model is not found, an HTTP exception will be raised.
     * @param integer $id the ID of the model to be loaded
     * @return SBBan the loaded model
     * @throws CHttpException
     */

    /**
     * Performs the AJAX validation.
     * @param Comms $model the model to be validated
     */
    protected function performAjaxValidation($model)
    {
        if(isset($_POST['ajax']) && $_POST['ajax'] === 'comms-form') {
            echo CActiveForm::validate($model);
            Yii::app()->end();
        }
    }

    /**
     * Returns the data model based on the primary key given in the GET variable.
     * If the data model is not found, an HTTP exception will be raised.
     * @param integer $id the ID of the model to be loaded
     * @return SBBan the loaded model
     * @throws CHttpException
     */
    public function loadModel($id)
    {
        $model = Comms::model()->with('admin')->findByPk($id);

        if($model === null)
            throw new CHttpException(404,'The requested page does not exist.');

        return $model;
    }
}
