/* 
    Script to initialize all the filter-icons to allow filtering by filling in their values in the searchbar
    #issue 1089
*/

function initFilterButtons(){

    function init(){
        $(".filter-submissions").click(filter);
    }

    function filter(){
        const element = $(this);
        const searchbar = $("#filter-query");
        console.log(element.data("filter"));
        searchbar.val(element.data("filter"));
    }
}

export {initFilterButtons}