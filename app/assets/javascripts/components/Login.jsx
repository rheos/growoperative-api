var Login = createReactClass({
  getInitialState: function() {
    return {
      inviteCode: '',
      inviteClicked: false,
      snackbarText: '',
    };
  },

  handleLogin(e) {
    e.preventDefault();
    var that = this;
    var userInfo = {
      user_name: document.getElementById("user_name").value,
      password: document.getElementById("password").value
    }
    $.ajax({
      type: "POST",
      url: API_URL + "/login",
      dataType: "json",
      data: userInfo,
      error:  function(xhr, status, error) {
        that.updateLoginError(JSON.parse(xhr.responseText).message);
      },
      success: function(data, textStatus, jqXHR){
        console.log(jqXHR.getResponseHeader('access-token'))
        window.location.replace("/");
      },
    })
  },
  handleVerifyInviteCode(e) {
    var that = this;
    $.ajax({
      type: "POST",
      url: API_URL + "/v1/verify_invitation_code",
      dataType: "json",
      data: {
        invitation_token: that.state.inviteCode.replace(/[-,_,/]/g, "").replace(/\s/g, '')
      },
      error:  function(xhr, status, error) {
        snackbarLoad(that, JSON.parse(xhr.responseText).message)
      },
      success: function(data, textStatus, jqXHR){
        that.props.setInvitationCode(that.state.inviteCode)
        that.props.changePage("signup")
      },
    })
  },
  updateLoginError(str) {
    snackbarLoad(this, str)
  },
  _handleVerifyKeyPress (e)  {
    if(e.key=="Enter"){
      this.handleVerifyInviteCode(e)
    }
  },
  _handleLoginKeyPress (e)  {
    if(e.key=="Enter"){
      this.handleLogin(e)
    }
  },
  render() {
    return (
      <div className="box_form">
        {this.state.inviteClicked==false?<div>
        <h2 className="title align-center">Login</h2>
          <div className="text-center">
            <input id="user_name" placeholder="Username" className="inputField"  onKeyPress={(e)=>this._handleLoginKeyPress(e)}/>
            <input type="password" id="password" placeholder="Password" className="inputField"  onKeyPress={(e)=>this._handleLoginKeyPress(e)}/>
            <button onClick={(e)=>this.handleLogin(e)} className="submitButton">Submit</button>
          </div>
          <div className="mt-15">
            Please login or <a className="link" onClick={()=>this.setState({inviteClicked: true})}><b>enter code</b></a> to register
          </div>
        </div> :
        <div className="text-center">
          <input id="invite_code"  className="mt-15 inputField" placeholder="Invite Code" onKeyPress={(e)=>this._handleVerifyKeyPress(e)} onChange={(event)=>this.setState({inviteCode: event.target.value})} />
          <button className="submitButton" onClick={(e) => this.handleVerifyInviteCode(e)}>Submit</button>
          <div>
            <a className="link" onClick={()=>this.setState({inviteClicked: false})}><b>&larr; Back</b></a>
          </div>
        </div>}
        <div id="snackbar">{this.state.snackbarText}</div>
      </div>
    );
  }
});
