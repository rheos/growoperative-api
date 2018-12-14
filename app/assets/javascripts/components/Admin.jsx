var Admin = createReactClass({
  getInitialState() {
    return {
      data: [],
      chainLimit: 0,
      originChainLimit: 0,
      snackbarText: '',
    };
  },

  componentWillMount() {
    this.getChainLimit()
    this.getAllUsers()
  },
  saveLimit(e) {
    var that= this;
    if(this.state.chainLimit)
    { 
      if(this.state.chainLimit>=this.state.originChainLimit)
      {
        $.ajax({
         type: "POST",
         url: API_URL + "/v1/set_chain_limit",
         dataType: "json",
         data: {
           chain_limit: that.state.chainLimit
         },
         error:  function(xhr, status, error) {
           snackbarLoad(that, JSON.parse(xhr.responseText).message)
         },
         success: function(data, textStatus, jqXHR){
          snackbarLoad(that, 'Successfully Changed!')
         },
        })
      }
      else
        snackbarLoad(that, "To protect your users, Chain Limit couldn't be smaller than before!")

    }
    else
        snackbarLoad(that, "Please input the Chain Limit!")

  },
  getChainLimit(){
    var that = this;
     $.ajax({
      type: "GET",
      url: API_URL + "/v1/get_chain_limit",
      dataType: "json",
      error: function (xhr, status, error) {
        snackbarLoad(that, JSON.parse(xhr.responseText).message)
      },
      success: function (res) {
        console.log(res)
        that.setState({chainLimit: res.data.chain_limit, originChainLimit: res.data.chain_limit})
      },
    });
  },
  getAllUsers() {
    var that = this;
    $.ajax({
      type: "Get",
      url: API_URL + "/v1/users",
      dataType: "json",
      error:  function(xhr, status, error) {

      },
      success: function (res) {
        that.setState({data: res})
      },
    });
  },
  onSaveInviteLimit(id, invite_limit){
    var that=this;
    $.ajax({
      type: "Post",
      url: API_URL + "/v1/users/" + id + "/set_invitation_limit",
      dataType: "json",
      data: {
        invite_limit: parseInt(invite_limit)
      },
      error:  function(xhr, status, error) {

        snackbarLoad(that, JSON.parse(xhr.responseText).message)

      },
      success: function (res) {
        snackbarLoad(that, res.message)
        that.getAllUsers()
      },
    });
  },
  updateData(index, e){
    data = this.state.data;
    data[index].invite_limit = parseInt(e.target.value)+parseInt(data[index].invitations_count);
    this.setState({data: data})
    console.log(data)
  },

  _handleKeyPress (id, invitations_count, e)  {
    if(e.key=="Enter"){
      $(e.target).removeClass('active');
      this.onSaveInviteLimit(id, parseInt(invitations_count)+parseInt(e.target.value))
    }
  },

  _focusOutFromEditable(e) {
    $(e.target).removeClass('active')
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
    var that = this;
    return <div>
      <h1>Admin</h1>
      {this.checkIfType('admin') &&
      <div>
        <div className="limitWrap">
          Chain Limit :<input id="chain_limit"  onChange={(e)=>this.setState({chainLimit: e.target.value})} value={this.state.chainLimit} className="inputField limit"/>
        </div> 
        <button  className="submitButton" onClick={this.saveLimit}>Save Limits</button> 
      </div>}
      {this.state.data.length>0? <div><h3>All users in our system:</h3><table  className="mt-15">
        <thead>
          <tr>
            <td>Username</td>
            <td>Used Invite Code</td>
            <td>Depth</td>
            <td>Invites Count</td>
            <td>Invites Left</td>
            <td>Created At</td>
          </tr>
        </thead>
        <tbody>
          {
            this.state.data.map(function(user, index){
              var creatediffDays = Math.floor((new Date() - new Date(user.created_at)) / 86400000);
              var creatediffHrs = Math.floor(((new Date() - new Date(user.created_at)) % 86400000) / 3600000);
              var creatediffMins = Math.round((((new Date() - new Date(user.created_at)) % 86400000) % 3600000) / 60000);
              var creatediff = '';
              if(creatediffDays>0)
                creatediff = creatediffDays + ' days ago'
              else {
                if(creatediffHrs>0)
                  creatediff = creatediffHrs + ' hours ago'
                else
                  creatediff = creatediffMins + ' mins ago'
              }
              let isAdmin = false;
              console.log(user)
              user.user_groups.map(function(type, index){
                if(type.group_label == 'admin'){
                  isAdmin = true
                }
              })
              // var updatediffDays = Math.floor((new Date() - new Date(user.updated_at)) / 86400000);
              // var updatediffHrs = Math.floor(((new Date() - new Date(user.updated_at)) % 86400000) / 3600000);
              // var updatediffMins = Math.round((((new Date() - new Date(user.updated_at)) % 86400000) % 3600000) / 60000);
              // var updatediff = '';
              // if(updatediffDays>0)
              //   updatediff = updatediffDays + ' days ago'
              // else {
              //   if(updatediffHrs>0)
              //     updatediff = updatediffHrs + ' hours ago'
              //   else
              //     updatediff = updatediffMins + ' mins ago'
              // }
              return <tr key={index}>
                <td>
                  {user.user_name}
                </td>
                <td>
                  {user.invited_code?(user.invited_code).slice(0, 4)+' '+(user.invited_code).slice(4, 8):''}
                </td>
                <td>
                  {user.depth}
                </td>
                <td>
                  {user.invitations_count}
                </td>
                {isAdmin? 
                <td>
                  No Limit
                </td>:
                <td className="editable inviteNumber"  onClick={(e)=>console.log($(e.target).find('input').addClass('active').focus())}>
                  <input type="number" max="99" min="0" className="toggleInput" defaultValue={user.invite_limit - user.invitations_count}  onBlur ={that._focusOutFromEditable} onKeyPress={that._handleKeyPress.bind(that, user.id, user.invitations_count)}/>
                  {user.invite_limit - user.invitations_count}
                </td>}
                <td>
                  {creatediff}
                </td>
              </tr>
            })}
        </tbody>
      </table></div>:''}
      <div id="snackbar">{this.state.snackbarText}</div>
    </div>
  }
});
