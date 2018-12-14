var Contact = createReactClass({
  getInitialState() {
    return {
      data: [],
      relationShipPrices: [],
      categories: [],
      snackbarText: '',
    };
  },

  componentWillMount() {
    this.getContact()
    this.getUserRelationShipPrices()
    this.getCategories()
  },

  getCategories() {
    var that = this;
    $.ajax({
      type: "Get",
      url: API_URL + "/v1/categories",
      dataType: "json",
      error:  function(xhr, status, error) {
      },
      success: function(data, textStatus, jqXHR){
        that.setState({categories: data})
      },
    })
  },
  getUserRelationShipPrices() {
    var that = this;
    $.ajax({
      type: "Get",
      url: API_URL + "/v1/user_relationship_prices",
      dataType: "json",
      error:  function(xhr, status, error) {
      },
      success: function (res) {
        that.setState({relationShipPrices: res})
      },
    });
  },
  getContact() {
    var that = this;
    $.ajax({
      type: "Get",
      url: API_URL + "/v1/users/contact_list",
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
  updateContactName(user_id, friend_id, label){
    var that=this;
    console.log(user_id, friend_id)
    $.ajax({
      type: "PATCH",
      url: API_URL + "/v1/users/edit_contact_label",
      dataType: "json",
      data: {
        "first_id": that.props.user_id==user_id?friend_id:user_id,
        "second_id": that.props.user_id==user_id?user_id:friend_id,
        "new_label": label
      },
      error:  function(xhr, status, error) {
       
      },
      success: function(res){
        that.getContact()
      },
    })
  },
  updateRelationshipPrice(rel_id, friend_id, label){
    var that=this;
    $.ajax({
      type: "Post",
      url: API_URL + "/v1/user_relationship_prices",
      dataType: "json",
      data: {
        "user_relationship_price": {
          "category_id": 1,
          "friend_id": friend_id,
          "price": label,
          "relationship_id": rel_id
        }
      },
      error:  function(xhr, status, error) {
       
      },
      success: function(res){
        snackbarLoad(that, 'Relationship price is set successfully!')
        that.getUserRelationShipPrices()
      },
    })
  },
  _handleKeyPress (user_id, friend_id, e)  {
    if(e.key=="Enter"){
      $(e.target).removeClass('active');
      this.updateContactName(user_id, friend_id, e.target.value)
    }
  },
  _relationshipPriceUpdatePress (rel_id, id1, id2, e)  {
    if(e.key=="Enter"){
      $(e.target).parent().removeClass('active');
      let friend_id = this.props.user_id == id1? id2:id1
      this.updateRelationshipPrice(rel_id, friend_id, e.target.value)
    }
  },
  _focusOutFromEditable(e) {
    $(e.target).removeClass('active')
  },
  _focusOutFromEditableDiv(e) {
    $(e.target).parent().removeClass('active')
  },
  uniqueByGroupLabel(a) {
    return a.filter((e, i) => a.findIndex(e2 =>  e.group_label === e2.group_label) === i);
  },
  render() {
    var that=this;
    return (
      <div>
        {this.state.data.length>0? <div className="box_form big">
            <h2 className="title align-center">Contact Book</h2>
            {
              (this.state.data.length>0) && this.state.data.map(function(contact, index){
                // var diffDays = Math.floor((new Date() - new Date(contact.created_at)) / 86400000);
                // var diffHrs = Math.floor(((new Date() - new Date(contact.created_at)) % 86400000) / 3600000);
                // var diffMins = Math.round((((new Date() - new Date(contact.created_at)) % 86400000) % 3600000) / 60000);
                // var diff = '';
                var relationPrice = that.state.relationShipPrices.length>0?that.state.relationShipPrices.filter(relationPrice=> (relationPrice.user_id==that.props.user_id) && (relationPrice.friend_id==contact.friend_id)): 1
                var contactName = (that.props.user_id==contact.user_id?
                      (contact.friend_label?contact.friend_label: (contact.friend.nickname?contact.friend.nickname:contact.friend.user_name)):
                      (contact.user_label?contact.user_label: (contact.user.nickname?contact.user.nickname:contact.user.user_name)))
                // if(diffDays>0)
                //   diff = diffDays + ' days ago'
                // else {
                //   if(diffHrs>0)
                //     diff = diffHrs + ' hours ago'
                //   else
                //     diff = diffMins + ' mins ago'
                // }
                let markupPrice = relationPrice.length>0?checkPrice(relationPrice[0].price):(that.state.categories.length>0?checkPrice(that.state.categories[0].default_node_price):'');
                return <div key={index} className="contact">
                  <span  className="editable" >
                    {contactName} <i className="fa fa-pencil" onClick={(e)=>console.log($(e.target).parent().find('input').addClass('active').focus())}></i>
                    <input type="text" defaultValue={contactName} className="toggleInput" onBlur ={that._focusOutFromEditable} onKeyPress={that._handleKeyPress.bind(that, contact.user_id, contact.friend_id)} />
                  </span>
                  <span className="editableDiv">
                    <i className="fa fa-cog" title={markupPrice} onClick={(e)=>$(e.target).parent().find('div').addClass('active').find('input').focus()}></i>
                    <div className="toggleDiv">{contactName}'s markup: <input type="number" defaultValue={markupPrice} onBlur ={that._focusOutFromEditableDiv} onKeyPress={that._relationshipPriceUpdatePress.bind(that, contact.id, contact.user_id, contact.friend_id)}  /></div>
                  </span>
                  <span className="ml-10">
                    {that.props.user_id==contact.user_id?that.uniqueByGroupLabel(contact.friend.user_groups).map(user_group=>user_group.group_label).join(', '):
                    that.uniqueByGroupLabel(contact.user.user_groups).map(user_group=>user_group.group_label).join(', ')}
                  </span>
                  {/*<span>
                    {diff}
                  </span>*/}
                </div>
              }) }</div> : <p>No Users</p>}
        <div id="snackbar">{this.state.snackbarText}</div>
      </div>
    );
  }
});
