var Dashboard = createReactClass({
  getInitialState: function() {
    return {
      addItemForm: false,
      updateItemForm: false,
      listFixedWidth: 275,
      isListWidthAuto: false, 
      snackbarText: '',
      allNames: [
      ],
      allItems: [
        {
          listName: 'Available',
          listItems: []
        },
        {
          listName: 'Requested',
          listItems: []
        },
        {
          listName: 'Received',
          listItems: []
        },
        {
          listName: 'Shipped',
          listItems: []
        }
      ]
    };
  },
  componentDidMount(){
    this.getAllItems();
    this.getItemNames();
    this.getCategories();
    this.getGrades();
  }, 
  getAllItems() {
    var that = this;
    $.ajax({
      type: "Get",
      url: API_URL + "/v1/items",
      dataType: "json",
      error:  function(xhr, status, error) {
      },
      success: function(data, textStatus, jqXHR){
        var listItems=[];
        var allItems = that.state.allItems;
        if(data)
        	allItems[0].listItems = data.data;
        // if(data.data.length>0){
        //   data.data.map(function(item, index){
        //     listItems.push({"id":item.id, "itemTitle": item.attributes.quantity+" "+item.attributes['unit-name']+" "+item.attributes.name+" $"+item.attributes.price+"/"+item.attributes['unit-name']})
        
        //   })
        // }
        that.setState({allItems})
        that.initSortable();
      },
    })
  },
  getItemNames() {
    var that = this;
    $.ajax({
      type: "Get",
      url: API_URL + "/v1/item_names",
      dataType: "json",
      error:  function(xhr, status, error) {
      },
      success: function(data, textStatus, jqXHR){

        var allNames = [];
        if(data.length>0){
          data.map(function(name, index){
            allNames.push(name.name)
          })
        }
        that.setState({allNames})
      },
    })
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
  getGrades() {
    var that = this;
    $.ajax({
      type: "Get",
      url: API_URL + "/v1/grades",
      dataType: "json",
      error:  function(xhr, status, error) {
      },
      success: function(data, textStatus, jqXHR){
        that.setState({grades: data})
      },
    })
  },
  componentDidUpdate() {
    if(this.state.allNames.length>0)
      $( "#form_name" ).autocomplete({
        source: this.state.allNames
      });
  }, 
  compare(a,b) {
    if (a.id > b.id)
      return -1;
    if (a.id < b.id)
      return 1;
    return 0;
  },
  formatDate(date) {
      var d = new Date(date),
          month = '' + (d.getUTCMonth() + 1),
          day = '' + d.getUTCDate(),
          year = d.getUTCFullYear();

      if (month.length < 2) month = '0' + month;
      if (day.length < 2) day = '0' + day;

      return [year, month, day].join('-');
  },
  initSortable() {
    // $(".column").sortable({
    //     connectWith: ".column",
    //     handle: ".header",
    // });
    $("ul.droptrue").sortable({
        connectWith: "ul"
    });
    $("ul.dropfalse").sortable({
        connectWith: "ul",
    });
  },
  removeItem(item_id) {
    var that = this;
    $.ajax({
      type: "Delete",
      url: API_URL + "/v1/items/" + item_id,
      dataType: "json",
      error:  function(xhr, status, error) {
        snackbarLoad(that, 'You are not able to remove this item!')
      },
      success: function(data, textStatus, jqXHR){
        snackbarLoad(that, 'Item deleted!')
        that.getItemNames()
        that.getAllItems()
      },
    })
  },
  addItem(){
    var that = this;
    var name = $('#form_name').val();
    var category = $('#form_category').val()?$('#form_category').val():1;
    var grade = $('#form_grade').val();
    var quantity = $('#form_quantity').val();
    var unit = $('#form_unit').val();
    var price = $('#form_price').val();
    var date_available = $('#form_available').val();
    // if(Number.isInteger(Number(quantity))){
      if(name && category && grade && quantity && price && unit){
        $.ajax({
          type: "POST",
          url: API_URL + "/v1/items",
          dataType: "json",
          data: {
            "item": {
              "name": name,
              "category_id": category,
              "grade_id": grade,
              "quantity": quantity,
              "price": price,
              "unit": unit,
              "date_available": date_available,
              "organic": parseInt($('.addItemForm .organic').val())
            }
          },
          error:  function(xhr, status, error) {
          },
          success: function(data, textStatus, jqXHR){

            snackbarLoad(that, 'Item successfully added!')
            that.setState({addItemForm: false})
            that.getItemNames()
            that.getAllItems()
          },
        })
      }
      else {
        snackbarLoad(that, 'All fields are required!')
      }
  },
  addDays(date, days) {
    var result = new Date(date);
    result.setDate(date.getDate() + days);
    return result;
  },
  updateItem(){
    var that = this;
    var name = $('#update_form_name').val();
    var category = $('#update_form_category').val()?$('#update_form_category').val():1;
    var grade = $('#update_form_grade').val();
    var quantity = $('#update_form_quantity').val();
    var unit = $('#update_form_unit').val();
    var price = $('#update_form_price').val();
    var date_available = $('#update_form_available').val();
    // if(Number.isInteger(Number(quantity))){
      if(name && category && grade && quantity && price && unit){
        $.ajax({
          type: "PUT",
          url: API_URL + "/v1/items/"+that.state.editItem.id,
          dataType: "json",
          data: {
            "item": {
              "name": name,
              "category_id": category,
              "grade_id": grade,
              "quantity": quantity,
              "price": price,
              "unit": unit,
              "organic": parseInt($('.updateItemForm .organic').val()),
              "date_available": date_available
            }
          },
          error:  function(xhr, status, error) {
          },
          success: function(data, textStatus, jqXHR){
            snackbarLoad(that, 'Item successfully updated!')
            that.setState({updateItemForm: false})
            that.getItemNames()
            that.getAllItems()
          },
        })
      }
      else {
        snackbarLoad(that, 'All fields are required!')
      }

  },
  render() {

    var that = this
    return <div>
      <div className="orders">
        {
          (this.state.allItems.length>0) && this.state.allItems.map(function(list, index){
            return <div key={index} className={list.listName=='Available'?"column withadd":"column"} style={{width: that.state.isListWidthAuto? 'calc(25% - 8px)': that.state.listFixedWidth}}>
              <div className="box" data-title={list.listName}>
                <div className="header">
                  {list.listName}
                </div>
                <div className="body ">
                  <ul className="droptrue sortable">
                    {
                      (list.listItems.length>0) && list.listItems.map(function(item, itemIndex){
                        return <li key={itemIndex}  onClick={(e)=>{that.setState({viewItemForm: true, editItem: item})}} className={item.attributes['user-id']==that.props.user_id?"ui-state-highlight own":"ui-state-highlight"}>
                          <div className="itemCard">
                            <div className="quantity">
                              {checkIfQuantity(item.attributes.quantity)}
                            </div>
                            <div className="price">
                              {"$"+checkPrice(item.attributes['total-price'])}
                            </div>
                            <div className="grade">
                              {that.state.grades && (that.state.grades.length>0) && that.state.grades.find(function(grade){
                                return grade.id == item.attributes['grade-id']
                              }).name}
                            </div>
                            <div className="itemName">
                              {item.attributes['target-user-name']}{/*item.attributes.price*/}
                            </div>
                            <div className="itemTitle">
                              {item.attributes.name}
                            </div>
                            {/*item.attributes.quantity+" "+item.attributes['unit-name']+" "+item.attributes.name+" $"+item.attributes.price+"/"+item.attributes['unit-name']*/}
                          </div>
                          {that.props.user_id==item.attributes['user-id'] && <i className="fa fa-edit" onClick={(e)=>{e.stopPropagation();that.setState({updateItemForm: true, editItem: item})}}></i>}
                          {that.props.user_id==item.attributes['user-id'] && <i className="fa fa-trash" onClick={(e)=>{e.stopPropagation();that.removeItem(item.id)}}></i>}
                        </li>
                      })
                    }
                  </ul>
                  {list.listName=="Available" && <p onClick={()=>that.setState({addItemForm: true})}>+ Add an item</p>}
                </div>
              </div>
            </div>
          })
        }
      </div>
      {this.state.addItemForm && <div className="addItemForm ui-widget" onClick={()=>that.setState({addItemForm: false})}>
        <div className="content" onClick={(e)=>e.stopPropagation()}>
          <h3 className="align-center"> Add New Item </h3>
          <div className="formField">
            <label>Category:</label> 
            <input type="text" className="unselectable" readOnly value={that.state.categories && (that.state.categories.length>0) && that.state.categories[0].category_name}/>
            {/*<select id="form_category">
              {
                that.state.categories && (that.state.categories.length>0) && that.state.categories.map(function(category, index){
                  return <option key={index} value={category.id}>{category.category_name}</option>
                })
              }
            </select>*/}
          </div>
          <div className="formField">
            <label>Quantity:</label> <input id="form_quantity" type="number"/>
          </div>
          <div className="formField">
            <label>Name:</label> <input id="form_name" className="ui-autocomplete-input"/>
          </div>
          <div className="formField">
            <label>Price:</label> <input id="form_price" type="number"/>
          </div>
          <div className="formField">
            <label>Grade:</label> 
            <select id="form_grade">
              {
                that.state.grades && (that.state.grades.length>0) && that.state.grades.sort(that.compare).map(function(grade, index){
                  return <option key={index} value={grade.id}>{grade.name}</option>
                })
              }
            </select>
          </div>
          <div className="formField organform">
            <label>Organic:</label>
            <div>
              <input className="organic" type="radio" name="organic" value={1} /> Y
              <input className="organic" type="radio" name="organic" value={0} defaultChecked /> N
            </div>
          </div>
          <div className="formField">
            {/* <label>Unit:</label> <input id="form_unit" type="text"/> */}
            <input id="form_unit" type="hidden" value="lbs"/>
          </div>
          <div className="formField">
            <label>Available Date:</label> <input id="form_available" type="date" min={that.formatDate(new Date())} max={that.formatDate(that.addDays(new Date(), 12))} defaultValue={that.formatDate(new Date())}/>
          </div>
          <div className="formField mt-15 align-center">
            <button className="submitButton" onClick={that.addItem}>
              Add Item
            </button>
          </div>
        </div>
      </div>}

      {this.state.updateItemForm && <div className="updateItemForm ui-widget" onClick={()=>that.setState({updateItemForm: false})}>
        <div className="content" onClick={(e)=>e.stopPropagation()}>
          <h3 className="align-center"> Update Item </h3>
          <div className="formField">
            <label>Category:</label> 
            <input type="text" className="unselectable" readOnly value={that.state.categories && (that.state.categories.length>0) && that.state.categories[0].category_name}/>
            {/*<select id="update_form_category" defaultValue={that.state.editItem.attributes['category-id']}>
              {
                that.state.categories && (that.state.categories.length>0) && that.state.categories.map(function(category, index){
                  return <option key={index} value={category.id}>{category.category_name}</option>
                })
              }
            </select>*/}
          </div>
          <div className="formField">
            <label>Quantity:</label> <input id="update_form_quantity" type="number" defaultValue={checkIfQuantity(that.state.editItem.attributes.quantity)}/>
          </div>
          <div className="formField">
            <label>Name:</label> <input id="update_form_name" className="ui-autocomplete-input" defaultValue={that.state.editItem.attributes.name}/>
          </div>
          <div className="formField">
            <label>Price:</label> <input id="update_form_price" type="number" defaultValue={checkPrice(that.state.editItem.attributes.price)}/>
          </div>
          <div className="formField">
            <label>Grade:</label> 
            <select id="update_form_grade" defaultValue={that.state.editItem.attributes['grade-id']}>
              {
                that.state.grades && (that.state.grades.length>0) && that.state.grades.sort(that.compare).map(function(grade, index){
                  return <option key={index} value={grade.id}>{grade.name}</option>
                })
              }
            </select>
          </div>
          <div className="formField organform">
            <label>Organic:</label>
            <div>
              <input className="organic" type="radio" name="organic" value={1} defaultChecked={that.state.editItem.attributes.organic==true?true:false}/> Y
              <input className="organic" type="radio" name="organic" value={0} defaultChecked={that.state.editItem.attributes.organic==false?true:false}/> N
            </div>
          </div>
          <div className="formField">
            {/*<label>Unit:</label> <input id="update_form_unit" type="text" defaultValue={that.state.editItem.attributes['unit-name']}/> */}
            <input id="update_form_unit" type="hidden" value="lbs"/>
          </div>
          <div className="formField">
            <label>Available Date:</label> <input id="update_form_available" type="date" defaultValue={that.state.editItem.attributes['date-available']?that.formatDate(that.state.editItem.attributes['date-available']):that.formatDate(new Date())}
            min={that.state.editItem.attributes['created-at']?that.formatDate(that.state.editItem.attributes['created-at']):that.formatDate(new Date())}
            max={that.state.editItem.attributes['created-at']?that.formatDate(that.addDays(new Date(that.state.editItem.attributes['created-at']), 12)):that.formatDate(that.addDays(new Date(), 12))}/>
          </div>
          <div className="formField mt-15 align-center">
            <button className="submitButton" onClick={that.updateItem}>
              Update Item
            </button>
          </div>
        </div>
      </div>}

      {this.state.viewItemForm && <div className="viewItemForm ui-widget" onClick={()=>that.setState({viewItemForm: false})}>
        <div className="content" onClick={(e)=>e.stopPropagation()}>
          <h3 className="align-center"> {that.state.editItem.attributes.name} </h3>
          <div className="formField">
            <label>Category: {that.state.categories && (that.state.categories.length>0) && that.state.categories[0].category_name}</label> 

          </div>
          <div className="formField">
            <label>Quantity: {checkIfQuantity(that.state.editItem.attributes.quantity)}</label>
          </div>
          <div className="formField">
            <label>Price: {checkPrice(that.state.editItem.attributes['total-price'])}</label>
          </div>
          <div className="formField">
            <label>Grade: {that.state.editItem.attributes['grade-id']}</label> 
          </div>
          <div className="formField">
            <label>Available Date: {that.state.editItem.attributes['date-available']?that.formatDate(that.state.editItem.attributes['date-available']):that.formatDate(new Date())}</label> 
          </div>
        </div>
      </div>}

      <div className="footer">
        <p className="widthMode"><span onClick={()=>this.setState({isListWidthAuto: !this.state.isListWidthAuto})}>{this.state.isListWidthAuto?"fixed width columns":"variable width columns"}</span></p>
      </div>
      <div id="snackbar">{this.state.snackbarText}</div>
    </div>
  }
});
