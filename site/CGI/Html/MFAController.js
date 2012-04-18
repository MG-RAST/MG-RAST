function FBAview (formId, rxnId, geneId, cpdId, mfaComponentId) {
    var MFAviewIds = new Array();'FBAview','4_tab_1','4_tab_4','4_tab_2',''
    var MFAerrorIds = new Array();
    $('#' + formId + ' input').each(function() {
        if($(this).attr('checked')) {
            if($(this).hasClass('noGrowth')) {
                MFAerrorIds.push($(this).attr('value')); 
            } else {
                MFAviewIds.push($(this).attr('value'));
            }
        }
    });
    
    var RunIds = new Array();
    var Models = new Array();
    // SplitMFAviewIds a MODEL,RUN_ID into [MODEL] and [RUN_ID]
    for(var i=0; i < MFAviewIds.length; i++) {
        var tmp = new Array();
        var tmp = MFAviewIds[i].split('_');
        if(tmp.length != 2) { console.log("Invalid runId passed: " + MFAviewIds[i]); }
        Models.push(tmp[0]); 
        RunIds.push(MFAviewIds[i]); 
    } 

    // Compare current models to selected. 
    var CurrentModels = new Array();
    CurrentModels = $('#model').val().split(',');
    var needToReload = 0;
    if(CurrentModels.length == Models.length ) {
        for( var i=0; i < Models.length; i++) {
            var noneFound = 1;
            for( var j=0; j < CurrentModels.length; j++) {
                if(CurrentModels[j] == Models[i]) {
                    noneFound = 0;
                }
            }
            if ( noneFound ) {
                needToReload = 1;
                break;
            }
        }
    } else { needToReload = 1; }
    needToReload = 1;//Seems to be a bug with the code when the page does not reload, so we're always going to reload until this is fixed 
    if(needToReload) {
        // If there is a difference reload whole page...
        var cgi = 'fluxIds=' + RunIds.join(',') + '&model=' + Models.join(',') + '&tab=1';
        execute_ajax("output","content", cgi, "Loading fluxes for selected models...",0,"post_hook");
    } else {
        // Otherwise just reload the tables...
        var cgi = 'fluxIds=' + RunIds.join(',') + '&models=' + Models.join(',');
        var rxnParts = rxnId.split('_');
        var ajaxArray = ['output', rxnId, cgi, 'ReactionTable|rxnTbl'];
        FBAchangeTabViewAjax (rxnParts[0], rxnParts[2], ajaxArray);
    }
    if(MFAerrorIds.length == 1) {
        alert("You cannot view fluxes on simulations that did not grow. " + MFAerrorIds.length + " simulation will not be shown.");
    }
    if(MFAerrorIds.length > 1) {
        alert("You cannot view fluxes on simulations that did not grow. " + MFAerrorIds.length + " simulations will not be shown.");
    }
}

function FBAdelete ( formId ) {
    var fluxIds = new Array();
    $('#' + formId + ' input').each(function() {
        if($(this).attr('checked')) {
            fluxIds.push($(this).attr('value'));
        }
    });
    var fluxCgi = 'fluxIds=' + fluxIds.join(',');
    execute_ajax('delete_results', 'fbaResultsTable', fluxCgi, 'Loading...', 0, 'post_hook', 'MFBAController|mfba_controller'); 
}

function FBArun ( formId ) {
    var form = document.getElementById(formId);
    var media = form.media.value;
    var model = modelIds.join(',');
    FBAloadMissingTabs(0,4,'fbaResultsTable', 20, function() {
        execute_ajax('FBArun', 'fbaResultsTable', "media="+ media + "&model=" + model,
            'Loading...', 0, 'post_hook', 'MFBAController|mfba_controller');
        });
}

function FBAloadMissingTabs (tabViewerId, tabId, tabContentId, maxWaitTime, postHook) {
    tab_view_select(tabViewerId, tabId);
    FBAwaitForMissingContent(tabContentId, maxWaitTime, postHook);
}
    
function FBAwaitForMissingContent (contentId, maxWaitTime, postHook) {
    var waitTime = 0;
    var done = 0;
    var waitIntervalId = setInterval(function () {
        if (document.getElementById(contentId)) {
            done = 1;
            postHook();
        } else {
            waitTime += 0.5;
        }
        if (waitTime > maxWaitTime || done) {
            clearInterval(waitIntervalId);
        }
    }, 500);
}

function FBAchangeTabViewAjax (tabViewId, tabId, ajaxSetupArray) {
    tab_view_select(tabViewId, tabId);
    var div = $('#' + tabViewId + "_content_" + tabId);
    var ajaxDiv = $('#' + tabViewId + "_tabajax_" + tabId);
    if(div && ajaxDiv) {
        var newTabAjax = [0];
        newTabAjax = newTabAjax.concat(ajaxSetupArray);
        ajaxDiv.attr('value', newTabAjax.join(';'));
    }
    if(div && div.hasClass('tab_view_content_selected')) {
        tab_view_select(tabViewId, tabId);
    }
}
