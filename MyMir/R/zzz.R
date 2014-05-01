.onLoad <- function(lib,pkg) {

    require(methods);

    assign("MyMirEnv", new.env(), .GlobalEnv); # mi creo un mio environment in cui custodire gelosamente alcune variabili globali del package
    
    # Database of target predictions settings
    odbc.dsn = "mirna"; # string, Data Source Name; configure /etc/odbc.ini file before changing default value ("mirna")
    odbc.pw = "korda"; # string, password to access to database
    db.usr = "dario";
    db.pw = odbc.pw;
    db.host = "155.253.6.97";
    db.name = "mm9";
#     odbc.dsn <- readline("Data Source Name [mirna]: ")
#     if (odbc.dsn == "") { odbc.dsn <- "mirna"; }
#     odbc.pw <- readline ("Database Password: ")
    
    # assegnazione delle variabili al mio environment;
    # per reperirle successivamente occorre un comando tipo:
    #   get("odbc.dsn", envir=MyMirEnv)
    assign("odbc.dsn", odbc.dsn, envir=MyMirEnv); 
    assign("odbc.pw", odbc.pw, envir=MyMirEnv);
    assign("db.usr", db.usr, envir=MyMirEnv);
    assign("db.pw", db.pw, envir=MyMirEnv);
    assign("db.host", db.host, envir=MyMirEnv);
    assign("db.name", db.name, envir=MyMirEnv);
}