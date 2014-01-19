<?php
/* @var $this CommsController */
/* @var $plugin CommsPlugin */
/* @var $comms Comms */
/* @var $comment SBComment */
/* @var $hideInactive string */
/* @var $total_punishments integer */

?>

<?php $summaryText = CHtml::link(
    $hideInactive == 'true' ? Yii::t('CommsPlugin.main', 'Show inactive punishments') : Yii::t('CommsPlugin.main', 'Hide inactive punishments'),
    array('', 'hideinactive' => $hideInactive == 'true' ? 'false' : 'true')) . ' | <em>' . Yii::t('CommsPlugin.main', 'Total punishments') . ': ' . $total_punishments . '</em>'; ?>

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
    'dataProvider'=>$comms->search(array(
        'scopes' => $hideInactive ? 'active' : null,
    )),
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
                'CHtml::image(Comms::getIcon($data->type,"' . CHtml::asset($plugin->getPath('assets')) . '"), Comms::getType($data->type))',
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
            'value'=>'$data->adminName',
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
            'value'=>'$data->lengthText',
        ),
    ),
    'afterAjaxUpdate'=>'js:createSections',
    'cssFile'=>false,
    'itemsCssClass'=>'items table table-accordion table-condensed table-hover',
    'nullDisplay'=>CHtml::tag('span', array('class'=>'null'), Yii::t('zii', 'Not set')),
    'pager'=>array(
        'class'=>'bootstrap.widgets.TbPager',
    ),
    'rowHtmlOptionsExpression'=>'array(
        "class"=>"header" . ($data->isExpired ? " expired" : ($data->isUnbanned ? " unbanned" : "")),
        "data-key"=>$data->primaryKey,
        "data-name"=>$data->name,
        "data-steam"=>$data->steam,
        "data-datetime"=>Yii::app()->format->formatDatetime($data->create_time),
        "data-datetime-expired"=>$data->expireText,
        "data-datetime-unbanned"=>$data->unbanTimeText,
        "data-length"=>$data->lengthText,
        "data-reason"=>$data->reason,
        "data-unban-reason"=>$data->unban_reason,
        "data-admin-name"=>$data->adminName,
        "data-unban-admin-name"=>$data->unbanAdminName,
        "data-server-id"=>$data->server_id,
        "data-community-id"=>$data->communityId,
        "data-comments-count"=>$data->commentsCount,
        "data-type"=>$data->type,
    )',
    'pagerCssClass'=>'pagination pagination-right',
    'selectableRows'=>0,
    'summaryText'=>$summaryText,
)) ?><!-- comms grid -->

</section>

<script id="comms-section" type="text/x-template">
  <table class="table table-condensed pull-left">
    <tbody>
      <tr>
        <th><?php echo $comms->getAttributeLabel('name') ?></th>
        <td><%=header.data("name") || nullDisplay %></td>
      </tr>
      <tr>
        <th><?php echo $comms->getAttributeLabel('steam') ?></th>
        <td>
          <%=header.data("steam") || nullDisplay %>
<% if(header.data("communityId")) { %>
          (<a href="http://steamcommunity.com/profiles/<%=header.data("communityId") %>" target="_blank"><?php echo Yii::t('sourcebans', 'View Steam Profile') ?></a>)
<% } %>
        </td>
      </tr>
      <tr>
        <th><?php echo Yii::t('sourcebans', 'Invoked on') ?></th>
        <td><%=header.data("datetime") %></td>
      </tr>
<% if(header.data("datetimeExpired")) { %>
      <tr>
        <th><?php echo Yii::t('sourcebans', 'Expires on') ?></th>
        <td><%=header.data("datetimeExpired") %></td>
      </tr>
<% } %>
<% if(header.data("datetimeUnbanned")) { %>
      <tr>
        <th><?php echo Yii::t('CommsPlugin.main', 'Removed on') ?></th>
        <td><%=header.data("datetimeUnbanned") %></td>
      </tr>
<% } %>
      <tr>
        <th><?php echo $comms->getAttributeLabel('length') ?></th>
        <td><%=header.data("length") %></td>
      </tr>
      <tr>
        <th><?php echo $comms->getAttributeLabel('reason') ?></th>
        <td><%=header.data("reason") || nullDisplay %></td>
      </tr>
<?php if(!(Yii::app()->user->isGuest && SourceBans::app()->settings->bans_hide_admin)): ?>
      <tr>
        <th><?php echo $comms->getAttributeLabel('admin.name') ?></th>
        <td><%=header.data("adminName") %></td>
      </tr>
<?php endif ?>
<% if(header.data("serverId")) { %>
      <tr>
        <th><?php echo $comms->getAttributeLabel('server_id') ?></th>
        <td class="ServerQuery_hostname"><?php echo Yii::t('sourcebans', 'components.ServerQuery.loading') ?></td>
      </tr>
<% } %>
<% if(header.data("datetimeUnbanned")) { %>
      <tr>
        <th><?php echo Yii::t('CommsPlugin.main', 'Reason for removal') ?></th>
        <td><%=header.data("unbanReason") || nullDisplay %></td>
      </tr>
<?php if(!(Yii::app()->user->isGuest && SourceBans::app()->settings->bans_hide_admin)): ?>
      <tr>
        <th><?php echo Yii::t('CommsPlugin.main', 'Removed by') ?></th>
        <td><%=header.data("unbanAdminName") %></td>
      </tr>
<?php endif ?>
<% } %>
    </tbody>
  </table>
  <div class="ban-menu pull-right">
<?php $this->widget('zii.widgets.CMenu', array(
    'items' => array_merge(array(
        // array(
        //     'label' => Yii::t('sourcebans', 'Edit'),
        //     'url' => array('bans/edit', 'id'=>'__ID__'),
        //     'visible' => !Yii::app()->user->isGuest,
        // ),
        array(
            'label' => 'Undo punishment',
            'url' => '#',
            'itemOptions' => array('class' => 'comms-menu-unban'),
            'visible' => !Yii::app()->user->isGuest && Yii::app()->user->data->hasPermission('UNBAN_OWN_COMMS', 'UNBAN_GROUP_COMMS', 'UNBAN_ALL_COMMS'),
        ),
        // array(
        //     'label' => Yii::t('sourcebans', 'Delete'),
        //     'url' => array('bans/delete', 'id'=>'__ID__'),
        //     'itemOptions' => array('class' => 'ban-menu-delete'),
        //     'visible' => !Yii::app()->user->isGuest && Yii::app()->user->data->hasPermission('DELETE_BANS'),
        // ),
        array(
            'label' => Yii::t('sourcebans', 'Comments'),
            'url' => array('comments/index', 'object_type'=>Comms::COMMENTS_TYPE, 'object_id'=>'__ID__'),
            'itemOptions' => array('class' => 'comms-menu-comments'),
            'visible' => !Yii::app()->user->isGuest && Yii::app()->user->data->hasPermission('ADD_BANS'),
        ),
    ), $this->menu),
    'htmlOptions' => array(
        'class' => 'nav nav-stacked nav-pills',
    ),
)) ?>
  </div>
</script>

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

<?php Yii::app()->clientScript->registerScript('site_comms_hashchange', '
  $(window).bind("hashchange", function(e) {
    var id       = $.param.fragment();
    var $header  = $("#comms-grid tr[data-key=\"" + id + "\"]");
    var $section = $header.next("tr.section").find("div:first-child");

    $("#comms-grid > table.table-accordion > tbody > tr.selected").removeClass("selected");
    $("#comms-grid tr.section div:first-child").not($section).slideUp(200, "linear");
    if(!$header.length)
      return;

    $header.addClass("selected");
    $section.slideDown(200, "linear");
    $("#SBComment_object_id").val(id);
  });

  $(document).on("click.yiiGridView", "#comms-grid tr.header", function(e) {
    var $this     = $(this);
    location.hash = $this.hasClass("selected") ? 0 : $this.data("key");
  });
  $(document).on("click.yiiGridView", "#comms-grid tr.header :checkbox", function(e) {
    e.stopImmediatePropagation();
  });
') ?>

<?php Yii::app()->clientScript->registerScript('site_comms_createSections', '
  var unbanTranslations = ' . Comms::getUnbanJsonTranslations() . ';

  function createSections() {
    var nullDisplay = "' . addslashes($grid->nullDisplay) . '";

    $("#comms-grid tr[data-key]").each(function(i, header) {
      $section = $("<tr class=\"section\"><td colspan=\"" + header.cells.length + "\"><div></div></td></tr>").insertAfter($(header));

      $section.find("div").html($("#comms-section").template({
        header: $(header),
        nullDisplay: nullDisplay
      }));
      $section.find("a").each(function() {
        this.href = this.href.replace("__ID__", $(header).data("key"));
      });
      if($(header).hasClass("expired") || $(header).hasClass("unbanned")) {
        $section.find(".comms-menu-unban").addClass("disabled");
      }
      else {
        $section.find(".comms-menu-unban a").prop("rel", $(header).data("key"));
      }
      $section.find(".comms-menu-comments a").append(" (" + $(header).data("commentsCount") + ")");
      $section.find(".comms-menu-unban a").html(unbanTranslations[$(header).data("type")]["unban"]);
    });

    updateSections();
    $(window).trigger("hashchange");
  }
  function updateSections() {
    if(typeof(window.serverInfo) == "undefined")
      return;

    $.each(window.serverInfo, function(i, server) {
      var $section = $("#comms-grid tr[data-server-id=\"" + server.id + "\"]").next("tr.section");
      $section.find(".ServerQuery_hostname").html(server.error ? server.error.message : server.hostname);
      $("#SBBan_server_id option[value=\"" + server.id + "\"]").html(server.error ? server.error.message : server.hostname);
    });
  }

  $(document).on("click", ".ban-menu-delete a", function(e) {
    if(!confirm("' . Yii::t('zii', 'Are you sure you want to delete this item?') . '")) return false;
    $("#' . $grid->id . '").yiiGridView("update", {
      type: "POST",
      url: $(this).attr("href"),
      success: function(data) {
        $("#' . $grid->id . '").yiiGridView("update");
      }
    });
    return false;
  });

  $(document).on("click", ".comms-menu-unban a", function(e) {
    if($(this).parents("li").hasClass("disabled"))
      return;

    var header = $("#comms-grid tr[data-key=\"" + $(this).prop("rel") + "\"]");
    var name = header.data("name") ? header.data("name") : header.data("steam");

    document.getElementById("confirm_title").innerHTML = unbanTranslations[header.data("type")]["unban_reason"];
    document.getElementById("confirm_text").innerHTML = unbanTranslations[header.data("type")]["unban_confirmation"].replace("__NAME__", name);
    document.getElementById("confirm_button").innerHTML = unbanTranslations[header.data("type")]["unban"];

    $("#confirm_button").prop("rel", $(this).prop("rel"));
    $("#unban-confirm").modal("show"); return false;
  });

  createSections();
') ?>


<?php Yii::app()->clientScript->registerScript('site_comms_queryServer', '
  $.getJSON("' . $this->createUrl('servers/info') . '", function(servers) {
    window.serverInfo = servers;

    updateSections();
  });
') ?>

<?php $this->beginWidget('bootstrap.widgets.TbModal', array('id'=>'unban-confirm')); ?>
<div class="modal-header">
    <a class="close" data-dismiss="modal">&times;</a>
    <h4 id="confirm_title">Unban reason</h4>
</div>

<div class="modal-body">
    <p id="confirm_text">Please give a short comment, why you are going to unban &laquo;name&raquo;:</p>
    <div class="modal-form">
            <textarea size="60" maxlength="255" id="unban_reason"></textarea>
    </div>
</div>

<div class="modal-footer">
    <?php $this->widget('bootstrap.widgets.TbButton', array(
        'type'=>'primary',
        'label'=>'Unban',
        'url'=>'#',
        'htmlOptions'=>array(
            'id' => 'confirm_button',
            'onclick' => '
                $.post("' . $this->createUrl('comms/unban', array("id" => "__ID__")) . '".replace("__ID__", $(this).prop("rel")), {
                  reason: $("#unban_reason").val()
                }, function(result) {
                  if(result == "true") {
                    $("#' . $grid->id . '").yiiGridView("update");
                  } else {
                    $.alert("' . Yii::t('CommsPlugin.main', 'An error was occurred, code: {code}', array('code' => 101)) . '", "warning");
                  }
                }).fail(function(jqXHR, textStatus) {
                  $.alert(jqXHR.responseText, "error");
                });
                $("#unban_reason").val("");
                $("#unban-confirm").modal("hide");
            '
        ),
    )); ?>
    <?php $this->widget('bootstrap.widgets.TbButton', array(
        'label'=>Yii::t('CommsPlugin.main', 'Cancel'),
        'url'=>'#',
        'htmlOptions'=>array('data-dismiss'=>'modal'),
    )); ?>
</div>
<?php $this->endWidget(); ?>


<?php if(!Yii::app()->user->isGuest && Yii::app()->user->data->hasPermission('ADD_BANS')): ?>
<div aria-hidden="true" class="modal fade hide" id="comments-dialog" role="dialog">
  <div class="modal-header">
    <button aria-hidden="true" class="close" data-dismiss="modal" type="button">&times;</button>
    <h3><?php echo Yii::t('sourcebans', 'Comments') ?></h3>
  </div>
  <div class="modal-body">
  </div>
  <div class="modal-footer">
<?php $this->renderPartial('/comments/_form', array('model' => $comment)) ?>

  </div>
</div>

<?php Yii::app()->clientScript->registerScript('site_comms_commentsDialog', '
  $(document).on("click", ".comms-menu-comments a", function(e) {
    e.preventDefault();
    $("#comments-dialog .modal-body").load($(this).attr("href"), function(data) {
      this.scrollTop = this.scrollHeight - $(this).height();
      tinyMCE.execCommand("mceFocus", false, "SBComment_message");

      $("#comments-dialog").modal({
        backdrop: "static"
      });
    });
  });
  $("#comment-form").submit(function(e) {
    e.preventDefault();
    var $this = $(this);

    $.post($this.attr("action"), $this.serialize(), function(result) {
      if(!result)
        return;

      $this.find(":submit").attr("disabled", true);
      tinyMCE.activeEditor.setContent("");

      $("#comms-grid tr.selected").next("tr.section").find(".comms-menu-comments a").trigger("click");
      $("#' . $grid->id . '").yiiGridView("update");
    }, "json");
  });
') ?>
<?php endif ?>

