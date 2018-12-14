function checkIfQuantity(val){
	return parseFloat(val.toString())
}
function checkPrice(val){
	return val==parseInt(val)?parseInt(val):(parseFloat(val).toFixed(2))
}
function snackbarLoad(self, text) {
    var that=self;
    self.setState({snackbarText: text})
    $('#snackbar').addClass('show');
    setTimeout(
      function(){ 
        $('#snackbar').removeClass('show'); 
        that.setState({snackbarText: ''})
      }, 3000);
}