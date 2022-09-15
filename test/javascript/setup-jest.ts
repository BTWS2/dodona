import * as jQuery from "jquery";

declare let window: any;
declare let global: any;
window.$ = window.jQuery = jQuery;
global.$ = global.jQuery = jQuery;

// Mocking the I18N calls. The key itself will be returned as value.
global.I18n = {
    t: t => t,
    formatNumber: n => n.toString(),
    t_a: k => [],
};
