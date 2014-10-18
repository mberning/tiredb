$(document).ready(function () {
    //update the results div with response
    $('#search_form').bind('ajax:success', function(evt, data, status, xhr){
        $('#tires').html(xhr.responseText);
        calculate_diameter_difference();
    });
    
    //display throbber while searching
    $('#search_form').bind('ajax:beforeSend', function(evt, xhr, settings){
        $('span#throbber').css('background-image', 'url(/images/ajax-loader.gif?v=1)');
    });

    $('input#stock_diameter').Watermark('Stock Diameter (inches)').change(function() {
        calculate_diameter_difference();
    });
    
    // buttonify!
    $('span#reset_button').button();
    
    // reset
    $('span#reset_button').click(function(){
        location.reload(true);
    });
    
    // select all button for manufactures
    $('#search_form span#select_all_brands').click(function() {
        $('#search_form td#manufacturer_selection input').prop('checked', true);
        $('form#search_form input#page').attr('value', 0);
        $('#search_form').submit();
    });
    
    // select none button for manufacturers
    $('#search_form span#select_no_brands').click(function() {
        $('#search_form td#manufacturer_selection input').prop('checked', false);
        $('form#search_form input#page').attr('value', 0);
        $('#search_form').submit();
    });
    
    // select all button for types
    $('#search_form span#select_all_types').click(function() {
        $('#search_form td.tire_attributes div.types input').prop('checked', true);
        $('form#search_form input#page').attr('value', 0);
        $('#search_form').submit();
    });
    
    // select none button for types
    $('#search_form span#select_no_types').click(function() {
        $('#search_form td.tire_attributes div.types input').prop('checked', false);
        $('form#search_form input#page').attr('value', 0);
        $('#search_form').submit();
    });
    
    // select summer button for types
    $('#search_form span#select_summer_types').click(function() {
        $('#search_form td.tire_attributes div.types input').prop('checked', false);
        $('#search_form td.tire_attributes div.types input.summer').prop('checked', true);
        $('form#search_form input#page').attr('value', 0);
        $('#search_form').submit();
    });
    
    // select winter button for types
    $('#search_form span#select_winter_types').click(function() {
        $('#search_form td.tire_attributes div.types input').prop('checked', false);
        $('#search_form td.tire_attributes div.types input.winter').prop('checked', true);
        $('form#search_form input#page').attr('value', 0);
        $('#search_form').submit();
    });
    
    // load different searches as needed
    $('#search_form span#standard_search a, span#wheel_search a, span#staggered_search a, span#hardcore_search a').bind('ajax:success', function(evt, data, status, xhr){
        $('td#size_selection').html(xhr.responseText);
        $('#search_form').submit();
        evt.stopPropagation();
    });
    
    //kill the throbber on parent form
    $('#search_form span#standard_search a').bind('ajax:beforeSend', function(evt, xhr, settings){
        $('form#search_form').attr('action', '/standard_search');
        $('form#search_form input#page').attr('value', 0);
        evt.stopPropagation();
    });
    
    //kill the throbber on parent form
    $('#search_form span#wheel_search a').bind('ajax:beforeSend', function(evt, xhr, settings){
        $('form#search_form').attr('action', '/wheel_search');
        $('form#search_form input#page').attr('value', 0);
        evt.stopPropagation();
    });
    
    //kill the throbber on parent form
    $('#search_form span#staggered_search a').bind('ajax:beforeSend', function(evt, xhr, settings){
        $('form#search_form').attr('action', '/staggered_search');
        $('form#search_form input#page').attr('value', 0);
        evt.stopPropagation();
    });
    
    //kill the throbber on parent form
    $('#search_form span#hardcore_search a').bind('ajax:beforeSend', function(evt, xhr, settings){
        $('form#search_form').attr('action', '/hardcore_search');
        $('form#search_form input#page').attr('value', 0);
        evt.stopPropagation();
    });
    
    
    // any time something in the for changes submit the search
    $('#search_form input,select').change(function(){
        $('form#search_form input#page').attr('value', 0);
        $('#search_form').submit();
    });
    
    // tooltip for tire types
    $("div.types span[title]").tooltip({ position: "top center", tipClass: 'bigtooltip', offset: [10, 5]});
});

function calculate_diameter_difference() {
    pi = 3.14;
    var diam_regex = /^\d*\.?\d+$/g;
    stock_diam = diam_regex.exec($('input#stock_diameter').val());
    
    if(stock_diam) {
        stock_diam = stock_diam[0];
        stock_circumference = pi * stock_diam;
        
        $('table#tire_results tbody tr').each(calc_row);
    }
    else {
        $('table#tire_results tbody tr td.diff').removeClass('red').removeClass('green').text('');
    }
}

function calc_row(index, row) {
    var diam_regex = /^\d*\.?\d+$/g;
    tire_diam = diam_regex.exec($(row).find('td.diam').first().text());
    
    if(tire_diam) {
        tire_diam = tire_diam[0];
        tire_circumference = pi * tire_diam;
        diff = Math.round(((tire_circumference - stock_circumference) / stock_circumference) * 10000);

        $(row).find('td.diff').text((diff / 100) + '%');
        if(diff > 0)
            $(row).find('td.diff').removeClass('red').addClass('green');
        if(diff < 0)
            $(row).find('td.diff').removeClass('green').addClass('red');
    }
}
