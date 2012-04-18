function addRxnRow() {
	var numRxnSpan = document.getElementById('numRxns');
	var numRxns = parseInt(numRxnSpan.getAttribute('value')) + 1;
	numRxnSpan.setAttribute('value', numRxns);

	var tr = document.createElement('tr');
	if ((numRxns % 2) == 1) {
		tr.setAttribute('class', 'odd_row');
	} else {
		tr.setAttribute('class', 'even_row');
	}

	var td1 = createTableTd(document.createTextNode(numRxns));
	td1.setAttribute('width', '20px');
	td1.setAttribute('style', 'vertical-align:middle;');
	
	var input2 = document.createElement('input');
	input2.setAttribute('id', 'rxnEquation_'+numRxns);
	input2.setAttribute('name', 'rxnEquation_'+numRxns);
	input2.setAttribute('type', 'text');
	var td2 = createTableTd(input2);
	td2.setAttribute('style', 'vertical-align:middle;');

	var input3 = createTextInput('rxnName_'+numRxns);
	var td3 = createTableTd(input3);

	var input4 = createTextInput('rxnEnzyme_'+numRxns);
	var td4 = createTableTd(input4);

	var input5 = createTextInput('rxnPathway_'+numRxns);
	var td5 = createTableTd(input5);

	var input6 = createTextInput('rxnNote_'+numRxns);
	var td6 = createTableTd(input6);

	var input7 = document.createElement('input');
	input7.setAttribute('id', 'rxnPrivate_'+numRxns);
	input7.setAttribute('name', 'rxnPrivate_'+numRxns);
	input7.setAttribute('type', 'checkbox');
	var td7 = createTableTd(input7);
	td7.setAttribute('style', 'vertical-align:middle;');

	tr.appendChild(td1);
	tr.appendChild(td2);
	tr.appendChild(td3);
	tr.appendChild(td4);
	tr.appendChild(td5);
	tr.appendChild(td6);
	tr.appendChild(td7);

	var table = document.getElementById('rxnTable');
	table.tBodies[0].appendChild(tr);
}

function createTableTd(tdChild) {
	var td = document.createElement('td');
	td.setAttribute('class', 'table_row');
	td.appendChild(tdChild);
	return td;
}

function createTextInput(id) {
	var input = document.createElement('textarea');
	input.setAttribute('id', id);
	input.setAttribute('name', id);
	input.setAttribute('rows', '1');
	input.setAttribute('cols', '15');
	return input;
}