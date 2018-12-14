var MyAccount = createReactClass({
  getInitialState() {
    return {
      currentPassword: '',
      newPassword: '',
      confirmPassword: '',
      error: '',
      displayName: '',
      categories: [],
      snackbarText: '',
    };
  },

  componentWillMount() {
    this.getNickName();
    this.getCategories();
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
  updatePassword() {
    var that = this;
    $.ajax({
      type: "PATCH",
      url: API_URL + "/v1/users/update_password",
      dataType: "json",
      data: {
        "user": {"current_password": that.state.currentPassword, "password": that.state.newPassword,"password_confirmation": that.state.confirmPassword}
      },
      error:  function(xhr, status, error) {
        if(JSON.parse(xhr.responseText).message)
          snackbarLoad(that, JSON.parse(xhr.responseText).message)
        if(JSON.parse(xhr.responseText).password && (JSON.parse(xhr.responseText).password)[0])
          snackbarLoad(that, (JSON.parse(xhr.responseText).password)[0])
        else if(JSON.parse(xhr.responseText).password_confirmation && (JSON.parse(xhr.responseText).password_confirmation)[0])
          snackbarLoad(that, (JSON.parse(xhr.responseText).password_confirmation)[0])
      },
      success: function(res){
        snackbarLoad(that, res.message)
      },
    })
  },
  setNickName(nickname){
    var that=this;
    $.ajax({
      type: "PUT",
      url: API_URL + "/v1/users/" + this.props.user_id + "/set_nickname",
      dataType: "json",
      data: {
        "user": {"nickname": nickname }
      },
      error:  function(xhr, status, error) {
       
      },
      success: function(res){
        snackbarLoad(that, 'Display name changed!')
        that.getNickName();
      },
    })
  },
  updateCategoryPrice(price, id){
    var that=this;
    $.ajax({
      type: "POST",
      url: API_URL + "/v1/user_category_prices",
      dataType: "json",
      data: {
        "user_category_price": {
          "price": price, 
          "unit": 'lbs',
          "category_id": id
        }
      },
      error:  function(xhr, status, error) {
       
      },
      success: function(res){
        snackbarLoad(that, 'Markup Price Updated!')
        that.getCategories();
      },
    })
  },
  getNickName(){
    var that=this;
    $.ajax({
      type: "Get",
      url: API_URL + "/v1/users/" + this.props.user_id + "/get_nickname",
      dataType: "json",
     
      error:  function(xhr, status, error) {
        
      },
      success: function(res){
        that.setState({displayName: res.data.nick_name})
      },
    })
  },
  _handleKeyPress (e)  {
    if(e.key=="Enter"){
      $(e.target).removeClass('active');
      if(e.target.value)
        this.setNickName(e.target.value)
      else
        snackbarLoad(this, 'Please set correct display name!')
    }
  },
  _focusOutFromEditable(e) {
    $(e.target).removeClass('active')
  },
  _handleUpdateCategory(id, e) {
    if(e.key=="Enter"){
      $(e.target).removeClass('active');
      if(e.target.value)
        this.updateCategoryPrice(e.target.value, id)
      else
        snackbarLoad(this, 'Please enter the price!')
    }
  },
  render() {
    var that=this;
    return (
      <div className="box_form big align-left pl-50 myAccount">
        <h2 className="title align-center">My Account</h2>
        <div className="displayName editable">
          <h4  onClick={(e)=>console.log($('#displayName').addClass('active').focus())}>Display Name: {this.state.displayName?<span>{this.state.displayName}</span>:<span className="placeholder">{this.props.user_name}</span>}</h4>
          <input type="text" id="displayName" className="toggleInput"  onBlur ={this._focusOutFromEditable}  defaultValue={this.state.displayName}  onKeyPress={this._handleKeyPress} />
         
        </div><br/>
        <div className="update_category_price_form">
          {this.state.categories.filter(cat=> cat.id ==1).map(function(category, index){
            let price = category.user_category_prices.filter(price => price.user_id == that.props.user_id).length>0?category.user_category_prices.filter(price => price.user_id == that.props.user_id)[0].price:category.default_node_price;

            return <div key={index}>{/*category.category_name*/}<h4>Default Markup: 
              <div  className="editable"   onClick={(e)=>console.log($(e.target).find('input').addClass('active').focus())}>
                ${checkPrice(price)}<input type="text" className="toggleInput" onBlur= {that._focusOutFromEditable} onKeyPress={that._handleUpdateCategory.bind(that, category.id)} />
              </div> </h4>
            </div>
          })}
        </div>
        <div className="reset_password_form">
          
          <div>
            <h4>Change Password</h4>
            <div>
              <input type="password" placeholder="Current Password" value={this.state.currentPassword} onChange={(e)=>this.setState({currentPassword: e.target.value})}/>
              <input type="password" placeholder="New Password" value={this.state.newPassword} onChange={(e)=>this.setState({newPassword: e.target.value})}/>
              <input type="password" placeholder="Confirm Password" value={this.state.confirmPassword} onChange={(e)=>this.setState({confirmPassword: e.target.value})}/>
              <button onClick={(e)=>this.updatePassword(e)} className="submitButton">Submit</button>
            </div>
          </div>
        </div>
        <div id="snackbar">{this.state.snackbarText}</div>
      </div>
    );
  }
});
