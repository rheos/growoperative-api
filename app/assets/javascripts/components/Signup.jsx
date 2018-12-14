var Signup = createReactClass({
  getInitialState: function() {
    return {
      success: false,
      snackbarText: '',
    };
  },

  _handleSignupKeyPress (e)  {
    if(e.key=="Enter"){
      this.handleSignup(e)
    }
  },
  handleSignup(e) {
    e.preventDefault();
    var that = this;
    let password = document.getElementById("password").value;
    let password_confirmation = document.getElementById("password_confirmation").value
    var userInfo = {
      user_name: document.getElementById("user_name").value,
      password: password,
      password_confirmation: password_confirmation,
      invited_code: that.props.inviteCode.replace(/[-,_,/]/g, "").replace(/\s/g, '')
      // confirm_success_url: "http://192.168.0.6:3009"
    }
    if(password === password_confirmation){
      $.ajax({
        type: "POST",
        url: API_URL + "/signup",
        dataType: "json",
        data: {"user" : userInfo},
        error:  function(xhr, status, error) {
          snackbarLoad(that, 'Failed!')
        },
        success: function (res) {
          that.setState({success: true})
          window.location.replace("/");
        },
      });
    }
    else
       snackbarLoad(that, "Password doesn't match!")
  },


  render: function() {
    return (
      <div>
        {this.state.success ? <div><h3>You've registered successfully!</h3><a href='/'>Link To Login</a></div> :
        <div className="box_form">
          <h2 className="title align-center">Signup</h2>
          <div className="text-center">
            <input id="user_name" placeholder="Username" className="inputField"  onKeyPress={(e)=>this._handleSignupKeyPress(e)}/>
            <input type="password" id="password" placeholder="Password" className="inputField"  onKeyPress={(e)=>this._handleSignupKeyPress(e)}/>
            <input type="password" id="password_confirmation" placeholder="Retype Password" className="inputField"  onKeyPress={(e)=>this._handleSignupKeyPress(e)}/>
            <button onClick={(e)=>this.handleSignup(e)} className="submitButton">Submit</button>
          </div>
        </div>}
        <div id="snackbar">{this.state.snackbarText}</div>
      </div>
    );
  }
});
