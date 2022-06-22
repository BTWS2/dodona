import { createDelayer, fetch, getURLParameter, updateArrayURLParameter, updateURLParameter } from "util.js";
import { InactiveTimeout } from "auto_reload";
const RELOAD_SECONDS = 2;


export class QueryParameters<T> {
    params: Map<string, T> = new Map();
    listeners_by_key: Map<string, Array<(k: string, o: T, n: T)=>void>> = new Map();
    listeners: Array<(k: string, o: T, n: T)=>void> = [];

    resetParams(): void {
        this.params.forEach((v, k) => {
            if (v !== undefined) {
                this.updateParam(k, undefined);
            }
        });
    }

    updateParam(key: string, value: T): void {
        const old: T = this.params.get(key);
        if (old === value) {
            return;
        }

        this.params.set(key, value);

        this.listeners.forEach(f => f(key, old, value));
        const listeners = this.listeners_by_key.get(key);
        if (listeners) {
            listeners.forEach(f => f(key, old, value));
        }
    }

    subscribeByKey(key: string, listener: (k: string, o: T, n: T)=>void): void {
        const listeners = this.listeners_by_key.get(key);
        if (listeners) {
            listeners.push(listener);
        } else {
            this.listeners_by_key.set(key, [listener]);
        }
    }

    subscribe(listener: (k: string, o: T, n: T)=>void): void {
        this.listeners.push(listener);
    }
}

export class SearchQuery {
    updateAddressBar= true;
    autoSearch= true;
    baseUrl: string;
    refreshElement: string;
    periodicReload: InactiveTimeout;
    searchIndex = 0;
    appliedIndex = 0;
    arrayQueryParams: QueryParameters<string[]> = new QueryParameters<string[]>();
    queryParams: QueryParameters<string> = new QueryParameters<string>();

    setRefreshElement(refreshElement: string): void {
        this.refreshElement = refreshElement;

        if (this.refreshElement) {
            this.periodicReload = new InactiveTimeout(
                document.querySelector(this.refreshElement),
                RELOAD_SECONDS * 1000,
                () => {
                    this.search();
                }
            );
            this.refresh(this.queryParams.params.get("refresh"));
        } else {
            this.periodicReload = undefined;
        }
    }

    setBaseUrl(baseUrl?: string): void {
        this.updateAddressBar = baseUrl === undefined || baseUrl === "";
        const _url = baseUrl || window.location.href;
        const url = new URL(_url.replace(/%5B%5D/g, "[]"), window.location.origin);
        this.baseUrl = url.href;

        // Reset old params
        for (const key of this.arrayQueryParams.params.keys()) {
            this.arrayQueryParams.updateParam(key, undefined);
        }
        for (const key of this.queryParams.params.keys()) {
            this.queryParams.updateParam(key, undefined);
        }

        // initialise present parameters
        for (const key of url.searchParams.keys()) {
            if (key.endsWith("[]")) {
                this.arrayQueryParams.updateParam(key.substring(0, key.length-2), url.searchParams.getAll(key));
            } else {
                this.queryParams.updateParam(key, url.searchParams.get(key));
            }
        }
    }

    initPagination(): void {
        const remotePaginationButtons = document.querySelectorAll(".page-link[data-remote=true]");
        remotePaginationButtons.forEach(button => button.addEventListener("click", () => {
            const href = button.getAttribute("href");
            const page = getURLParameter("page", href);
            this.queryParams.updateParam("page", page);
        }));
    }

    constructor(baseUrl?: string, refreshElement?: string) {
        this.setBaseUrl(baseUrl);

        // subscribe relevant listeners
        this.arrayQueryParams.subscribe(k => this.paramChange(k));
        this.queryParams.subscribe(k => this.paramChange(k));
        this.queryParams.subscribeByKey("refresh", (k, o, n) => this.refresh(n));

        window.onpopstate = e => e.state && this.setBaseUrl();

        this.setRefreshElement(refreshElement);
    }

    addParametersToUrl(baseUrl?: string): string {
        let url: string = baseUrl || this.baseUrl;
        this.queryParams.params.forEach((v, k) => url = updateURLParameter(url, k, v));
        this.arrayQueryParams.params.forEach((v, k) => url = updateArrayURLParameter(url, k, v));

        return url;
    }

    resetAllQueryParams(): void {
        this.queryParams.resetParams();
        this.arrayQueryParams.resetParams();
    }

    refresh(value: string): void {
        if (this.periodicReload) {
            if (value === "true") {
                this.periodicReload.start();
            } else {
                this.periodicReload.end();
            }
        }
    }

    updateHistory(push: boolean): void {
        if (!this.updateAddressBar) {
            return;
        }
        const url = this.addParametersToUrl();
        if (url === window.location.href) {
            return;
        }
        if (push) {
            window.history.pushState(true, "Dodona", url);
        } else {
            window.history.replaceState(true, "Dodona", url);
        }
    }

    paramChangeDelayer = createDelayer();
    changedParams = [];
    paramChange(key: string): void {
        this.changedParams.push(key);
        this.paramChangeDelayer(() => {
            if (this.queryParams.params.get("page") !== "1" && this.changedParams.every(k => k !== "page")) {
                this.changedParams = [];
                this.queryParams.updateParam("page", "1");
                return;
            }
            this.updateHistory(this.changedParams.some(k => k === "page"));
            if (this.autoSearch) {
                this.search();
            }
            this.changedParams = [];
        }, 100);
    }

    search(): void {
        const url = this.addParametersToUrl();
        const localIndex = ++this.searchIndex;

        document.getElementById("progress-filter").style.visibility = "visible";
        fetch(updateURLParameter(url, "format", "js"), {
            headers: {
                "accept": "text/javascript"
            },
            credentials: "same-origin",
        })
            .then(resp => resp.text())
            .then(data => {
                if (this.appliedIndex < localIndex) {
                    this.appliedIndex = localIndex;
                    eval(data);
                }
                document.getElementById("progress-filter").style.visibility = "hidden";
            });
    }
}

dodona.searchQuery = dodona.searchQuery || new SearchQuery();
export const searchQuery = dodona.searchQuery;
