<?php
/**
 * This is the configuration for generating message translations
 * for the Yii framework. It is used by the 'yiic message' command.
 */
return array(
    'sourcePath'=>dirname(__FILE__).DIRECTORY_SEPARATOR.'..',
    'messagePath'=>dirname(__FILE__).DIRECTORY_SEPARATOR.'..'.DIRECTORY_SEPARATOR.'messages',
    'languages'=>array('cs','de','en','nl','ru','pt_br','pl'),
    'fileTypes'=>array('php'),
    'overwrite'=>true,
    'sort'=>true,
    'exclude'=>array(
        '.git',
        '.gitignore',
        '.gitattributes',
    ),
);
