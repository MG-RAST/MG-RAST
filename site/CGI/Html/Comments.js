/* ---------------------------------- */
/* Comments Functions                 */
/* ---------------------------------- */
// Requires jQuery
// Requires jQuery.timeago plugin

// change the "posted on" time to relative time.
jQuery(document).ready(function() {
	$('[class*=CommentTime]').timeago();
});

function postedit () {
	$('[class*=CommentTime]').timeago();
};

function postadd () {
	$('[class*=CommentTime]').timeago();
	var oldID = $('#TmpComment > .CommentBlock').attr('id');	
	var parts = oldID.split('_');
	var newID = parts[0] + '_' + parts[2] + '_' + parts[3];
	$('#TmpComment').attr('id',newID);
};

function CommentsToggle() {
	$('.Comment').slideToggle(100);
};

function prehook (callerID, ajaxFN, outputDivID, input, loadingTXT, loadTxtBool, postHook, path) {
	// first create the output div above yourself
	$("#" + callerID).before("<div class='Comment' id='" + outputDivID + "'>Posting...</div>");
	// then call the ajax function on that div ID
	execute_ajax(ajaxFN, outputDivID, input, loadingTXT, loadTxtBool, postHook, path);
	// finally clear the input of the caller form (?)
	$('#' + callerID + " textarea").attr('value','');	
};
	
