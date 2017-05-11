(($, E) ->
  "use strict"

  absoluteSum = () ->
    $('#computation-results').css({
        position: 'absolute',
        bottom: '0px',
        'max-width': $('#computation-results').closest('table').width() + 'px'
      })
    count = 0
    $("#computation-results > td").each ->
      totest = $(this).closest('table').find($('thead > tr > th'))[count]
      # console.log($(totest).width())
      $(this).css('max-width', 'none')
      $(this).width($(totest).width())
      count++


  $(document).ready () ->
    absoluteSum()

    $('.list-selector').click () ->
      $('#computation-results > td > div').each ->
        console.log($(this).parent().width())
        myParent = $(this).parent()
        myWidth = myParent.width()
        myClass = myParent.attr('class')
        if $('.' + myClass).width() != myWidth
          $('.' + myClass).width(myWidth)

) jQuery, ekylibre
