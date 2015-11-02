set serveroutput on
declare
  /* Constants */
  c_schema                    CONSTANT varchar2(30) := 'REPLACE';
  /* Variables */
  v_exist                              varchar2(1) := 'N';
  /* Exceptions */
  e_invalid_schema                     exception;

begin

  -- --------------------------------------------------------------------------
  -- You must replace the c_schema constant in the declaration section above
  -- --------------------------------------------------------------------------
  if (c_schema = 'REPLACE') then
    raise e_invalid_schema;
  end if;

  dbms_output.put_line('_____________________________________________________________________________');

  begin
    select 'Y'
      into v_exist
      from dba_tables
     where owner = upper(c_schema)
       and table_name = 'LOGGER_ERROR_LKUP';

    dbms_output.put_line('LOGGER_ERROR_LKUP Table already exists, will skip table creation');

  exception
    when no_data_found then
      v_exist := 'N';
  end;

  if (v_exist = 'N') then
    dbms_output.put_line('LOGGER_ERROR_LKUP Table does not exist, will create table');
    execute immediate
      'create table '||c_schema||'.logger_error_lkup
        ( pk_id                            number not null enable,
          error_category_name              varchar2(500 byte),
          error_id                         integer,
          error_short_description          varchar2(500 byte),
          error_long_description           varchar2(4000 byte),
          create_user_id                   varchar2(250) not null enable,
          create_date                      timestamp(6)  not null enable,
          update_user_id                   varchar2(250) not null enable,
          update_date                      timestamp(6)  not null enable,
       constraint logger_error_lkup_pk primary key (pk_id))';

    dbms_output.put_line('LOGGER_ERROR_LKUP Table created');

  end if;

  dbms_output.put_line('_____________________________________________________________________________');
  v_exist := 'N';

  begin
    select 'Y'
      into v_exist
      from dba_tables
     where owner = upper(c_schema)
       and table_name = 'LOGGER_ERROR_XREF';

    dbms_output.put_line('LOGGER_ERROR_XREF Table already exists, will skip table creation');

  exception
    when no_data_found then
      v_exist := 'N';
  end;

  if (v_exist = 'N') then
    dbms_output.put_line('LOGGER_ERROR_XREF Table does not exist, will create table');
    execute immediate
      'create table '||c_schema||'.logger_error_xref
       (  logger_id number not null enable,
          error_id number,
          create_user_id varchar2(250 byte) not null enable,
          create_date timestamp (6) not null enable,
          update_user_id varchar2(250 byte) not null enable,
          update_date timestamp (6) not null enable,
       constraint logger_error_xref_pk primary key (logger_id))';

    dbms_output.put_line('LOGGER_ERROR_LKUP Table created');

  end if;

  dbms_output.put_line('_____________________________________________________________________________');

execute immediate 'create or replace PACKAGE '||c_schema||q'[.raiser AS

--  Ver#    ---Date---  --- Done-By ---     ----- What-Was-Done -----------------------------------
--  0.70    13 Jul 2015 Dan Gillis          New Package
--
--  Purpose:
--  1. Package allows you to raise an exception leveraging all of the logger functionality (through
--       the logger PLUGIN_FN_ERROR plugin) as well as raise your own unique exception ID.  This
--       allows you not to be constrained by Oracle's -20000 to 20999 range - you define your own!
--       There are examples of how to use the package at https://github.com/gilcrest/raiser, as
--       well as how to raise and catch an exception
--

  type error_rt is record (
    logger_id                        logger_logs.id%type,
    is_ora_error                     boolean,
    error_id                         logger_error_lkup.error_id%type,
    error_text                       varchar2(490));

  -- ----------------------------------------------------------------------------------------------
  -- proc is called by the logger.log_error PLUGIN_FN_ERROR plugin
  -- ----------------------------------------------------------------------------------------------
  procedure logger_raiser_plugin (p_rec in logger.rec_logger_log);

  -- ----------------------------------------------------------------------------------------------
  -- Function takes in the SQLERRM from a thrown exception (using either the
  --  raise_anticipated_exception or the raise_unanticipated_exception) as a varchar2 and parses
  --  it based on the consistent format used by both procedures
  -- ----------------------------------------------------------------------------------------------
  function getErrorDetails (p_sqlerrm in varchar2) return error_rt;

  -- ----------------------------------------------------------------------------------------------
  -- Proc uses logger.log_error along with plugin to raise an exception to the caller as well
  --  as log the error to the logger_logs table.  Allows for the logger unique ID to be passed to
  --  the caller in the exception message as well as an optional persisted error message that is
  --  defined in the PREDEFINED_ERROR_LKUP lookup table.  Both error message ID's (the unique logger
  --  ID and the optional persistent lookup ID will start your exception message text using the
  --  following consistent format: |logID:1234|errID:5678|you put in bad data, please don't do that
  -- ----------------------------------------------------------------------------------------------
  procedure raise_error (
    p_text                           in varchar2         default null,
    p_scope                          in varchar2         default null,
    p_extra                          in clob             default null,
    p_params                         in logger.tab_param default logger.gc_empty_tab_param,
    p_error_id                       in logger_error_lkup.error_id%type);

  -- ----------------------------------------------------------------------------------------------
  -- Proc uses logger.log_error along with plugin to raise an exception to the caller as well
  --  as log the error to the logger_logs table.  Allows for the logger unique ID to be passed to
  --  the caller in the exception message as well as an optional persisted error message that is
  --  defined in the PREDEFINED_ERROR_LKUP lookup table.  Both error message ID's (the unique logger
  --  ID and the optional persistent lookup ID will start your exception message text using the
  --  following consistent format: |logID:75|errID:-1476|divisor is equal to zero
  -- ----------------------------------------------------------------------------------------------
  procedure raise_ora_error (
    p_text                           in varchar2         default null,
    p_scope                          in varchar2         default null,
    p_extra                          in clob             default null,
    p_params                         in logger.tab_param default logger.gc_empty_tab_param,
    p_sqlcode                        in number,
    p_sqlerrm                        in varchar2);

end raiser;
]';

execute immediate 'create or replace PACKAGE BODY '||c_schema||q'[.raiser AS

--  Ver#    ---Date---  --- Done-By ---     ----- What-Was-Done -----------------------------------
--  0.70    13 Jul 2015 Dan Gillis          New Package
--
--  Purpose:
--  1. Package allows you to raise an exception leveraging all of the logger functionality (through
--       the logger PLUGIN_FN_ERROR plugin) as well as raise your own unique exception ID.  This
--       allows you not to be constrained by Oracle's -20000 to 20999 range - you define your own!
--       There are examples of how to use the package at https://github.com/gilcrest/raiser, as
--       well as how to raise and catch an exception
--

  -- ------------------------------------------------------------------------------------------------
  -- PRIVATE function to parse the JSON string out from the the logger_logs table
  -- ------------------------------------------------------------------------------------------------
  function parse_logger_text (p_logger_logs_rt IN logger_logs%rowtype)
    return varchar2 AS

  /* Variables */
  v_rsr_tilde_position             integer;
  v_json_start_bracket_position    integer;
  v_end_of_json_position           integer;
  v_json_end_bracket_position      integer;
  v_JSONstring_substr_length       integer;
  v_json_text                      varchar2(32767);

  begin

    v_rsr_tilde_position := instr(p_logger_logs_rt.text,'rsr~{',1,1);
    v_json_start_bracket_position := instr(p_logger_logs_rt.text,'{',v_rsr_tilde_position,1);
    v_end_of_json_position := instr(p_logger_logs_rt.text,'"e":0',1,1);
    v_json_end_bracket_position := instr(p_logger_logs_rt.text,'}',v_end_of_json_position,1);

    v_JSONstring_substr_length := ((v_json_end_bracket_position + 1) - v_json_start_bracket_position);

    v_json_text := substr(p_logger_logs_rt.text,v_json_start_bracket_position,v_JSONstring_substr_length);

    return v_json_text;

  end parse_logger_text;

  -- ------------------------------------------------------------------------------------------------
  -- PRIVATE function to return a JSON object as a varchar2 for the error text as part of the raised
  --  exception.
  --  Return is formatted as:
  --   {"loggerID":1623988,
  --    "isORAerror":false,
  --    "errorID":1234,
  --    "errorText":"You put in bad data, don\u0027t do that"
  --    }
  -- ------------------------------------------------------------------------------------------------
  function getJSONerrorString (p_logger_id IN integer,
                               p_error_id  IN integer,
                               p_error_text IN varchar2,
                               p_is_for_log IN boolean,
                               p_is_ora_error IN boolean)
    return varchar2 AS

  /* Variables */
  v_errorString_varchar2           varchar2(4000);

  /* Clobs */
  v_errorString_clob               clob;

  begin

    apex_json.initialize_clob_output;
    apex_json.open_object();

    if (p_logger_id is not null) then
      apex_json.write('loggerID', p_logger_id);
    end if;

    if (p_is_ora_error is not null) then
      apex_json.write('isORAerror', p_is_ora_error);
    end if;

    apex_json.write('errorID', p_error_id);
    apex_json.write('errorText', p_error_text);

    if (p_is_for_log) then
      apex_json.write('e',0); -- help denote the end of string when parsing out from log record
    end if;

    apex_json.close_object();
    v_errorString_clob := apex_json.get_clob_output;
    apex_json.free_output;

    v_errorString_varchar2 := cast(v_errorString_clob as varchar2);

    return v_errorString_varchar2;

  end getJSONerrorString;

  -- ------------------------------------------------------------------------------------------------
  -- PRIVATE proc to insert error data into xref table
  -- ------------------------------------------------------------------------------------------------
  procedure insert_logger_error_xref (p_logger_error_xref_rt IN logger_error_xref%rowtype) AS

    PRAGMA AUTONOMOUS_TRANSACTION;

  begin
    insert into logger_error_xref (logger_id,
                                   error_id,
                                   create_user_id,
                                   create_date,
                                   update_user_id,
                                   update_date)
                            values (p_logger_error_xref_rt.logger_id,
                                    p_logger_error_xref_rt.error_id,
                                    p_logger_error_xref_rt.create_user_id,
                                    sysdate,
                                    p_logger_error_xref_rt.update_user_id,
                                    sysdate);
    commit;
  end insert_logger_error_xref;

  -- ----------------------------------------------------------------------------------------------
  -- proc is called by the logger.log_error PLUGIN_FN_ERROR plugin
  -- ----------------------------------------------------------------------------------------------
  procedure logger_raiser_plugin (p_rec in logger.rec_logger_log) AS

  /* Record Types */
  v_logger_logs_rt                 logger_logs%rowtype;
  v_logger_error_xref_rt           logger_error_xref%rowtype;

  /* Local Variables */
  v_JSON_string                    varchar2(32767);
  v_error_id                       integer;
  v_error_text                     varchar2(32767);
  v_sqlerrm                        varchar2(1000);
  v_is_oracle_error                boolean;

  begin
    -- --------------------------------------------------------------------------------------------
    -- Get logger_logs record - eventually this step will be eliminated as the full logger_logs
    --   record type will be passed through as part of Logger enhancement #102
    -- --------------------------------------------------------------------------------------------
    select *
      into v_logger_logs_rt
      from logger_logs
     where id = p_rec.id;

    -- --------------------------------------------------------------------------------------------
    -- If there is no rsr~{ characters in the logger text, then this is a regular logger.log_error
    --   call.  Program will "return" as we do not want to raise any error in this case...
    --   logger.log_error calls should still function as originally designed (i.e., just log...)
    -- --------------------------------------------------------------------------------------------
    if (instr(v_logger_logs_rt.text,'rsr~{',1,1) = 0) then
      return;
    end if;

    v_json_string := parse_logger_text (p_logger_logs_rt => v_logger_logs_rt);

    apex_json.parse(p_source => v_json_string, p_strict => true);

    -- --------------------------------------------------------------------------------------------
    -- Get errorID
    -- --------------------------------------------------------------------------------------------
    v_error_id := apex_json.get_number(p_path => 'errorID');

    -- --------------------------------------------------------------------------------------------
    -- Get errorText
    -- --------------------------------------------------------------------------------------------
    v_error_text := apex_json.get_varchar2(p_path => 'errorText');

    -- --------------------------------------------------------------------------------------------
    -- Get isORAerror
    -- --------------------------------------------------------------------------------------------
    v_is_oracle_error := apex_json.get_boolean(p_path => 'isORAerror');

    -- --------------------------------------------------------------------------------------------
    -- If parse and variable setting above is successful, write the xref record
    --   and raise the application error with JSON format for error text
    --   TODO: Add Oracle Error
    -- --------------------------------------------------------------------------------------------
    v_logger_error_xref_rt.logger_id := p_rec.id;
    v_logger_error_xref_rt.error_id := v_error_id;
    v_logger_error_xref_rt.create_user_id := v_logger_logs_rt.user_name;
    v_logger_error_xref_rt.create_date := v_logger_logs_rt.time_stamp;
    v_logger_error_xref_rt.update_user_id := v_logger_logs_rt.user_name;
    v_logger_error_xref_rt.update_date := v_logger_logs_rt.time_stamp;

    insert_logger_error_xref(p_logger_error_xref_rt => v_logger_error_xref_rt);

    v_sqlerrm := getJSONerrorString (p_logger_id => p_rec.id,
                                     p_error_id => v_error_id,
                                     p_error_text => v_error_text,
                                     p_is_for_log => false,
                                     p_is_ora_error => v_is_oracle_error);

    raise_application_error(-20723,v_sqlerrm);

  end logger_raiser_plugin;

  -- ---------------------------------------------------------------------------------------------
  -- Function takes in the SQLERRM as a varchar2 from a thrown exception, using either the
  --  raise_anticipated_exception or raise_unanticipated_exception procs
  --  and parses it based on the JSON format used as part of the logger_raiser_plugin
  -- ---------------------------------------------------------------------------------------------
  FUNCTION getErrorDetails (p_sqlerrm in varchar2)
    return error_rt AS

  /* Record Type */
  v_rec_error                      error_rt;

  /* Variables */
  v_1st_curly_position             integer;
  v_sqlerrm                        varchar2(1000);
  v_is_oracle_error                boolean;

  begin

    -- ---------------------------------------------------------------------------------------------------
    --  Return is formatted as:
    --   ORA-20723: {"loggerID":1623988,
    --    "isORAerror":false,
    --    "errorID":1234,
    --    "errorText":"You put in bad data, don\u0027t do that"
    --    }
    --
    -- Need to remove the "ORA-20723: " from the sqlerrm format, so want to substr from first curly
    --   bracket to the end of the string
    -- ---------------------------------------------------------------------------------------------------
    v_1st_curly_position := instr(p_sqlerrm,'{',1,1);

    v_sqlerrm := substr(p_sqlerrm,v_1st_curly_position);

    -- ---------------------------------------------------------------------------------------------------
    -- use apex_json to parse the JSON string (using the varchar2 overloaded method)
    --   not sure why strict = true is not working when I'm using apex to do the write... will open bug
    -- ---------------------------------------------------------------------------------------------------
    apex_json.parse(p_source => v_sqlerrm, p_strict => true);

    -- --------------------------------------------------------------------------------------------
    -- Get loggerID and set value in record
    -- --------------------------------------------------------------------------------------------
    v_rec_error.logger_id := apex_json.get_number(p_path => 'loggerID');

    -- --------------------------------------------------------------------------------------------
    -- Get isORAerror
    -- --------------------------------------------------------------------------------------------
    v_rec_error.is_ora_error := apex_json.get_boolean(p_path => 'isORAerror');

    -- --------------------------------------------------------------------------------------------
    -- Get errorID and set value in record
    -- --------------------------------------------------------------------------------------------
    v_rec_error.error_id := apex_json.get_number(p_path => 'errorID');

    -- --------------------------------------------------------------------------------------------
    -- Get errorText and set value in record
    -- --------------------------------------------------------------------------------------------
    v_rec_error.error_text := apex_json.get_varchar2(p_path => 'errorText');

    return v_rec_error;

  end getErrorDetails;

  -- ------------------------------------------------------------------------------------------------
  -- Proc uses logger.log_error along with plugin to raise an exception to the caller as well
  --  as log the error to the logger_logs table.  Allows for the logger unique ID to be passed to
  --  the caller in the exception message as well as an optional persisted error message that is
  --  defined in the PREDEFINED_ERROR_LKUP lookup table.  Both error message ID's (the unique logger
  --   ID and the optional persistent lookup ID will start your exception message text using the
  --   following consistent format: |logID:1234|errID:5678|
  -- ------------------------------------------------------------------------------------------------
  procedure raise_error (
    p_text                           in varchar2         default null,
    p_scope                          in varchar2         default null,
    p_extra                          in clob             default null,
    p_params                         in logger.tab_param default logger.gc_empty_tab_param,
    p_error_id                       in logger_error_lkup.error_id%type) AS

  /* Local Variables */
  v_error                          varchar2(32767);
  v_JSON_error                     varchar2(32767);

  /* Exceptions */
  e_null_error_id                  exception;
  e_no_rsr_tilde                   exception;

  begin

    if (p_error_id is null) then
      raise e_null_error_id;
    elsif (instr(p_text,'rsr~',1,1) > 0) then
      raise e_no_rsr_tilde;
    end if;

    v_JSON_error := getjsonerrorstring(p_logger_id => null,
                                       p_error_id => p_error_id,
                                       p_error_text => p_text,
                                       p_is_for_log => true,
                                       p_is_ora_error => false);

    v_error := ('rsr~'||v_JSON_error);

    logger.log_error(p_text => v_error,
                     p_scope => p_scope,
                     p_extra => p_extra,
                     p_params => p_params);

  exception
    when e_null_error_id
      then raise_application_error(-20000,'p_error_id input parameter cannot be null, when using raise_anticipated_exception');
    when e_no_rsr_tilde
      then raise_application_error(-20001,'p_text input parameter cannot have "rsr~" within it');

  end raise_error;

  -- ------------------------------------------------------------------------------------------------
  -- Proc uses logger.log_error along with plugin to raise an exception to the caller as well
  --  as log the error to the logger_logs table.  Allows for the logger unique ID to be passed to
  --  the caller in the exception message as well as an optional persisted error message that is
  --  defined in the PREDEFINED_ERROR_LKUP lookup table.  Both error message ID's (the unique logger
  --   ID and the optional persistent lookup ID will start your exception message text using the
  --   following consistent format: |logID:1234|errID:5678|
  -- ------------------------------------------------------------------------------------------------
  procedure raise_ora_error (
    p_text                           in varchar2         default null,
    p_scope                          in varchar2         default null,
    p_extra                          in clob             default null,
    p_params                         in logger.tab_param default logger.gc_empty_tab_param,
    p_sqlcode                        in number,
    p_sqlerrm                        in varchar2) AS

  /* Local Variables */
  v_sqlcode                        varchar2(100);
  v_sqlerrm                        varchar2(512); -- SQLERRM max length is 512 bytes
  v_1st_colon_position             pls_integer;
  v_JSON_error                     varchar2(32767);
  v_error                          varchar2(32767);

  /* Exceptions */
  e_null_sqlcode                   exception;
  e_null_sqlerrm                   exception;

  begin

    if (p_sqlcode is null) then
      raise e_null_sqlcode;
    end if;

    if (p_sqlerrm is null) then
      raise e_null_sqlerrm;
    end if;

    v_1st_colon_position := instr(p_sqlerrm,':',1,1);
    v_sqlerrm := substr(p_sqlerrm,(v_1st_colon_position + 2),512);

    v_JSON_error := getjsonerrorstring(p_logger_id => null,
                                       p_error_id => p_sqlcode,
                                       p_error_text => v_sqlerrm,
                                       p_is_for_log => true,
                                       p_is_ora_error => true);

    v_error := ('rsr~'||v_JSON_error);

    logger.log_error(p_text => v_error,
                     p_scope => p_scope,
                     p_extra => p_extra,
                     p_params => p_params);

  exception
    when e_null_sqlcode
      then raise_application_error(-20000,'p_sqlcode input parameter cannot be null, when using raise_unanticipated_exception');

    when e_null_sqlerrm
      then raise_application_error(-20000,'p_sqlerrm input parameter cannot be null, when using raise_unanticipated_exception');

  end raise_ora_error;

end raiser;
]';

begin

  execute immediate
  'update '||c_schema||q'[.logger_prefs
      set pref_value = 'raiser.logger_raiser_plugin'
    where 1 = 1
      and pref_name = 'PLUGIN_FN_ERROR']';

  commit;

  execute immediate 'begin '||c_schema||'.logger_configure; end;';

end;

begin
  execute immediate 'begin '||c_schema||'.logger.status; end;';
end;

exception
  when e_invalid_schema then
    raise_application_error(-20722,'You must replace the c_schema constant value in the declaration section above');

end;
