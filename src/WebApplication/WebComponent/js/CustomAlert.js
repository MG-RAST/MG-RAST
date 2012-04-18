var CustomAlert = new Array();

function customAlert(id) {
  var html = CustomAlert[id];
  html = html.replace(/~!/g, '"');

  // shortcut reference to the document object
  var d = document;

  // if the modalContainer object already exists in the DOM, bail out.
  if(d.getElementById("modalContainer")) return;

  // create div that dims the content surrounding the alert box
  var dimContainer = d.getElementsByTagName("body")[0].appendChild(d.createElement("div"));
  dimContainer.setAttribute('id', 'dimContainer');
  dimContainer.setAttribute('style', 'position:fixed; width:100%; height:100%; top:0px; left:0px; background-color:black; opacity:0.0; filter:"alpha(opacity = 0)"; z-index:1000000;');
  opacity('dimContainer', 1, 80, 200);
	
  // create the modalContainer div as a child of the BODY element
  var mContainer = d.getElementsByTagName("body")[0].appendChild(d.createElement("div"));
  mContainer.setAttribute('id', 'modalContainer');
  mContainer.setAttribute('style', 'position:absolute; width:100%; height:100%; top:0px; left:0px; z-index:1000001;');

  // this div centers and acts as a table
  var mHeight = mContainer.appendChild(d.createElement("div"));
  mHeight.setAttribute('style', 'display: table; height: 100%; margin: 0 auto;');

  // this div acts as the cell and centers what's inside
  var mMiddle = mHeight.appendChild(d.createElement("div"));
  mMiddle.setAttribute('style', 'display: table-cell; vertical-align: middle;');

  // one more div to act as alert object
  var mAlert = mMiddle.appendChild(d.createElement("div"));
  mAlert.setAttribute('style', 'background-color: white; border: 2px solid #5DA668;');

  mAlert.innerHTML = html;
}

//removes the custom alert from the DOM
function removeCustomAlert() {
  opacity('dimContainer', 80, 1, 200);
  setTimeout('document.getElementsByTagName("body")[0].removeChild(document.getElementById("dimContainer"))', 200)
  document.getElementsByTagName("body")[0].removeChild(document.getElementById("modalContainer"));
}