var ViewUser = createReactClass({
  getInitialState: function() {
    return {
      user: null
    };
  },

  ViewUser(){
  	console.log(this.props.invitationCode)
    var that = this;
    $.ajax({
      type: "Patch",
      url: API_URL + "/v1/invitations/user_info",
      data: {
      	code: that.props.invitationCode.replace(/\s/g, '')
      },
      dataType: "json",
      error:  function(xhr, status, error) {
      },
      success: function(data, textStatus, jqXHR){
      	console.log(data.user)
      	that.setState({user:data.user})
      }, 
    })
  },
  componentWillMount() {
    this.ViewUser();
  },
  render() {
    return <div>
      <h1>ViewUser</h1>
      {
      	this.state.user && 
      	<div>
      		{this.state.user.nickname && <p>Display name: this.state.user.nickname</p>}
      		<p>Username: {this.state.user.user_name}</p>
      		<p>Invited Code: {this.state.user.invited_code}</p>
      		<p>Invite Limit: {this.state.user.invite_limit}</p>
      	</div>
      }
    </div>
  }
});
