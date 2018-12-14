var Navigation = createReactClass({
  getInitialState() {
    return {
      data: []
    };
  },

  componentWillMount() {
  },
  toggleDropdown(e) {
    $(e.target).parent().toggleClass('open');
  },
  checkIfType(user_type) {
    let flag=false;
    this.props.type.map(function(type, index){
      if(type.group_label == user_type){
        flag = true
      }
    })
    return flag
  },
  render() {    
    return (
      <ul className="navigation">
        <li className="logo"><h1>{this.props.siteName}</h1></li>
        <li className="dropdown">
          <p onClick={this.toggleDropdown}>{this.props.user?((this.props.user.user_name).charAt(0).toUpperCase()):''}</p>
          <ul>
            <li>
              <label>{this.props.user?(this.props.user.nickname?this.props.user.nickname+'('+this.props.user.user_name+')':this.props.user.user_name):''}</label>
            </li>
            <li>
              <a href="/MyAccount">My Account</a>
            </li>
            {(this.props.user && (this.checkIfType('admin')))?<li>
              <a href="/Admin">Admin Settings</a>
            </li>:''}
            <li>
              <Logout/>
            </li>
          </ul>
        </li>
        <li>
          <a href="/Invites">Invites</a>
        </li>
        <li>
          <a href="/Contact">Contacts</a>
        </li>
        <li>
          <a href="/">Dashboard</a>
        </li>
      </ul>
    );
  }
});
