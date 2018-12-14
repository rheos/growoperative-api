var Logout = createReactClass({

  handleLogout(e) {
  	var that= this;
    $.ajax({
      type: "DELETE",
      url: API_URL + "/logout",
      dataType: "json",
      success: function(data, textStatus, jqXHR){
        window.location.replace("/");
      },
    })
  },

  render: function() {
    return (
      <a className="link" onClick={this.handleLogout}>Sign Out</a>
    );
  }
});
