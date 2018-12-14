var Invites = createReactClass({
  getInitialState: function() {
    return {
      generatedCode: '',
      snackbarText: '',
      data: [],
      available_types: [],
      // showToggleView: false,
      inviteToAccept: '',
      selectedFilter: '',
    };
  },
  getInvites() {
    var that = this;
    $.ajax({
      type: "Get",
      url: API_URL + "/v1/invitations",
      dataType: "json",
      error:  function(xhr, status, error) {

        // console.log(xhr.responseText)
        // that.updateLoginError(JSON.parse(xhr.responseText).message);
      },
      success: function (res) {
        that.setState({data: res.data})
        //that.setState({errorMessage: '', success: true})
        //that.props.changePage("login");
      },
    });
  },
  componentWillMount(){
    console.log(this.props)
    this.getInvites()
    this.getAllUserType()
    if((this.state.chainLimit==0) && (this.checkIfType('admin')))
      this.getChainLimit()
  },
  generateCode(e){
    var that = this;
    e.preventDefault();
    $.ajax({
      type: "GET",
      url: API_URL + "/v1/users/generate_invitation",
      dataType: "json",
      data: {
        user_type: $('#generate_user_type').val()
      },
      error: function (xhr, status, error) {
        snackbarLoad(that, JSON.parse(xhr.responseText).message)
      },
      success: function (res) {
        that.setState({generatedCode: res.invitation_code})
        that.getInvites()
      },
    });
  },
  acceptInvite() {
    var that = this;
     $.ajax({
      type: "POST",
      url: API_URL + "/v1/users/accept_invition",
      dataType: "json",
      data: {
        invited_code: that.state.inviteToAccept.replace(/[-,_,/]/g, "").replace(/\s/g, '')
      },
      error: function (xhr, status, error) {
        snackbarLoad(that, JSON.parse(xhr.responseText).message)
      },
      success: function (res) {
        snackbarLoad(that, res.message)
      },
    });
  },
  toggleCodeView() {
    this.setState({showToggleView: !this.state.showToggleView})
  },
  _handleKeyPressLabel (id, e)  {
    if(e.key=="Enter"){
      $(e.target).removeClass('active');
      this.updateInvitationLabel(id, e.target.value)
    }
  },
  _handleKeyPressNote (id, e)  {
    if(e.key=="Enter"){
      $(e.target).removeClass('active');
      this.updateInvitationNote(id, e.target.value)
    }
  },
  updateInvitationLabel(id, label){
    var that=this;
    $.ajax({
      type: "PUT",
      url: API_URL + "/v1/invitations/" + id,
      dataType: "json",
      data: {
        "invitation": {"label": label}
      },
      error:  function(xhr, status, error) {
       
      },
      success: function(res){
        that.getInvites()
      },
    })
  },
  getAllUserType(){
    var that=this;
    $.ajax({
      type: "GET",
      url: API_URL + "/v1/available_user_type",
      dataType: "json",
      error:  function(xhr, status, error) {
       
      },
      success: function(res){
        that.setState({available_types: res.available_types})
      },
    })
  },
  updateInvitationNote(id, note){
    var that=this;
    $.ajax({
      type: "PUT",
      url: API_URL + "/v1/invitations/" + id + "/set_note_label",
      dataType: "json",
      data: {
        "note_label": note
      },
      error:  function(xhr, status, error) {
       
      },
      success: function(res){
        that.getInvites()
      },
    })
  },
  changeUserType(id, e){
    $(e.target).removeClass('active')
    var that=this;
    $.ajax({
      type: "PUT",
      url: API_URL + "/v1/invitations/" + id + "/set_user_type",
      dataType: "json",
      data: {
        "user_type": e.target.value
      },
      error:  function(xhr, status, error) {
       
      },
      success: function(res){
        that.getInvites()
      },
    })
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
  render: function() {
    var that=this;
    invitationCardsData = this.state.data;
    if((this.state.selectedFilter!='') && (invitationCardsData.length>0))
      invitationCardsData = invitationCardsData.filter(invitation => invitation.status == this.state.selectedFilter)
    return (
      <div className="box_form big">
        <h2 className="title align-center">My Invites</h2>
        <div className="align-center"> 
          <p className="mtb-5">{this.checkIfType('admin')? '' : this.props.inviteLimit - this.state.data.length+' left'}</p>
          {this.props.inviteLimit>this.state.data.length?<select id="generate_user_type">
            {that.state.available_types.map(function(type, index){
              return <option key={index}>{type}</option>
            })}
          </select>:''}
          {this.props.inviteLimit>this.state.data.length?<br/>:''}
          {(this.props.inviteLimit > this.state.data.length) && <button  className="submitButton mtb-5" onClick={this.generateCode}>Generate Code</button>} 
          {(this.props.inviteLimit > this.state.data.length) && <p className="mtb-5">{(this.state.generatedCode).slice(0, 4)+' '+(this.state.generatedCode).slice(4, 8)}</p>}
        </div>
        <hr/>
        <div className="align-center">
          <input type="text" className="align-center mtb-5 justify_center" placeholder="Enter Code" onChange={(e)=> this.setState({inviteToAccept: e.target.value})} value={this.state.inviteToAccept}/>
        </div>
        <div className="align-center">
          <button  className="submitButton" onClick={this.acceptInvite}>Accept Code</button> 
        </div>
        <div className="align-center">
          Filter: <select defaultValue={this.state.selectedFilter} onChange={(e)=>this.setState({selectedFilter:e.target.value})}>
            <option value="">Show All</option>
            <option value="accepted">Accepted</option>
            <option value="pending">Pending</option>
          </select>
        </div>
        <div>
          

          {(invitationCardsData.length>0) && <div>
              {
                invitationCardsData.map(function(invitation, index){
                  var diffDays = Math.floor((new Date() - new Date(invitation.created_at)) / 86400000);
                  var diffHrs = Math.floor(((new Date() - new Date(invitation.created_at)) % 86400000) / 3600000);
                  var diffMins = Math.round((((new Date() - new Date(invitation.created_at)) % 86400000) % 3600000) / 60000);
                  var diff = '';
                  if(diffDays>0)
                    diff = diffDays + ' days ago'
                  else {
                    if(diffHrs>0)
                      diff = diffHrs + ' hours ago'
                    else
                      diff = diffMins + ' mins ago'
                  }
                return <div className="invitationCard" key={index}>
                  <div className="code">
                    {(invitation.invitation_code).slice(0, 4)+' '+(invitation.invitation_code).slice(4, 8)}
                  </div>
                  <div className="status">
                    {invitation.status}
                  </div>
                  <div className={invitation.status=='accepted'?"label temp_disable":"label editable temp_disable"} onClick={(e)=>$(e.target).find('input').addClass('active').focus()}>
                    {invitation.label}
                    {invitation.status!='accepted' && <input type="text" defaultValue={invitation.label} className="toggleInput" onBlur ={that._focusOutFromEditable} onKeyPress={that._handleKeyPressLabel.bind(that, invitation.id)} />}
                  </div>
                  <div className={invitation.status=='accepted'?"note":"note editable"} onClick={(e)=>$(e.target).find('input').addClass('active').focus()}>
                    to :
                    {invitation.status=='accepted' && invitation.note_label? invitation.note_label: ''}
                    {(invitation.status!='accepted') && ( invitation.note_label?invitation.note_label:<span className='placeholder' onClick={(e)=>$(e.target).parent().find('input').addClass('active').focus()}>name</span>)}
                    {invitation.status!='accepted' && <input type="text" defaultValue={invitation.note_label} className="toggleInput" onBlur ={that._focusOutFromEditable} onKeyPress={that._handleKeyPressNote.bind(that, invitation.id)} />}
                  </div>
                  <div className={invitation.status=='accepted'?"userType":"userType editable"} onClick={(e)=>$(e.target).find('select').addClass('active').focus()}>
                    {invitation.user_type}
                    {invitation.status!='accepted' && <select  onBlur ={that._focusOutFromEditable} className="toggleInput" onChange={that.changeUserType.bind(that,invitation.id)} value={invitation.user_type}>
                      {that.state.available_types.map(function(type, index){
                        return <option key={index} >{type}</option>
                      })}
                    </select>}
                  </div>
                  <div className="time">
                    {diff}
                  </div>
                </div>
              })}
          </div>}



          {(invitationCardsData.length==0) && <p>No invite codes</p>}
        </div>
        <div id="snackbar">{this.state.snackbarText}</div>
      </div>
    );
  }
});
