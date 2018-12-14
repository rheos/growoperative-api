var Welcome = createReactClass({
  getInitialState: function() {
    return {
      page: "login",
      invitation_code: '',
    }
  },

  changePage: function(newPage) {
    this.setState({
      page: newPage
    });
  },

  setInvitationCode: function(code) {
    this.setState({
      invitation_code: code
    })
  },

  render: function() {
    switch(this.state.page) {
      case "login":
        return <Login changePage={this.changePage}  setInvitationCode={this.setInvitationCode} updateCurrentUser={this.updateCurrentUser}/>;
      case "signup":
        return <Signup changePage={this.changePage} inviteCode={this.state.invitation_code}/>;
      case "edit":
        return <Edit changePage={this.changePage}/>;
    }
  }
});
