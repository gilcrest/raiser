create table logger_error_lkup 
  (	pk_id                            number not null enable, 
    error_category_name              varchar2(500 byte), 
    error_id                         integer, 
    error_short_description          varchar2(500 byte), 
    error_long_description           varchar2(4000 byte), 
    create_user_id                   varchar2(250) not null enable,
    create_date                      timestamp(6)  not null enable, 
    update_user_id                   varchar2(250) not null enable,
    update_date                      timestamp(6)  not null enable, 
 constraint logger_error_lkup_pk primary key (pk_id))
/

create table logger_error_xref 
 (	logger_id number not null enable, 
    error_id number, 
    create_user_id varchar2(250 byte) not null enable, 
    create_date timestamp (6) not null enable, 
    update_user_id varchar2(250 byte) not null enable, 
    update_date timestamp (6) not null enable, 
 constraint logger_error_xref_pk primary key (logger_id))
/

create or replace PACKAGE       raiser AS

--  Ver#    ---Date---  --- Done-By ---     ----- What-Was-Done -----------------------------------
--  1.00    13 Jul 2015 Dan Gillis          New Package
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
  procedure raise_anticipated_exception (
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
  procedure raise_unanticipated_exception (
    p_text                           in varchar2         default null,
    p_scope                          in varchar2         default null,
    p_extra                          in clob             default null,
    p_params                         in logger.tab_param default logger.gc_empty_tab_param,
    p_sqlcode                        in number,
    p_sqlerrm                        in varchar2);

end raiser;
/
create or replace PACKAGE BODY                                                                                                                                                                   raiser AS

--  Ver#    ---Date---  --- Done-By ---     ----- What-Was-Done -----------------------------------
--  1.00    13 Jul 2015 Dan Gillis          New Package
--
--  Purpose:
--  1. Package allows you to raise an exception leveraging all of the logger functionality (through
--       the logger PLUGIN_FN_ERROR plugin) as well as raise your own unique exception ID.  This
--       allows you not to be constrained by Oracle's -20000 to 20999 range - you define your own!
--       There are examples of how to use the package at https://github.com/gilcrest/raiser, as 
--       well as how to raise and catch an exception
--

  -- ------------------------------------------------------------------------------------------------
  -- PRIVATE function to return a JSON object as a varchar2 for the error text as part of the raised
  --  exception.  
  --  Return is formatted as {"loggerID":123,"errorID":456,"errorText":"This is the error text"}
  -- ------------------------------------------------------------------------------------------------
  function getJSONerrorString (p_logger_id IN integer,
                               p_error_id  IN integer,
                               p_error_text IN varchar2)
    return varchar2 AS

  /* Variables */
  v_errorString_varchar2           varchar2(4000);

  /* Clobs */
  v_errorString_clob               clob;
  
  begin

    apex_json.initialize_clob_output;
    apex_json.open_object();
    apex_json.write('loggerID', p_logger_id);
    apex_json.write('errorID', p_error_id);
    apex_json.write('errorText', p_error_text);
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
  v_error_id                       integer;
  v_error_text                     varchar2(1000);
  v_1st_pipe_position              integer;
  v_2nd_pipe_position              integer;
  v_3rd_pipe_position              integer;
  v_errorID_substr_length          integer;
  v_errorText_substr_length        integer;
  v_sqlerrm                        varchar2(1000);
  
  begin
    -- --------------------------------------------------------------------------------------------
    -- Get logger_logs record - eventually this step will be eliminated as the full logger_logs 
    --   record type will be passed through as part of Logger enhancement #102
    -- --------------------------------------------------------------------------------------------
    select *
      into v_logger_logs_rt
      from logger_logs
     where id = p_rec.id;

    -- format is: |errorID|errorText|

    v_1st_pipe_position := instr(v_logger_logs_rt.text,'|',1,1);
    v_2nd_pipe_position := instr(v_logger_logs_rt.text,'|',1,2);
    v_3rd_pipe_position := instr(v_logger_logs_rt.text,'|',1,3);

    -- --------------------------------------------------------------------------------------------
    -- Get the length of the first chunk (from the 1st pipe to the 2nd) in order to be able to get
    --  the error ID
    -- --------------------------------------------------------------------------------------------
    v_errorID_substr_length := (v_2nd_pipe_position - 1) - v_1st_pipe_position;

    -- --------------------------------------------------------------------------------------------
    -- Parse error ID from the logger_logs table - perhaps someday, we can add an error_id column
    --  to logger_logs, but until then, I have to bake the error id somewhere into the existing 
    --  data structure and pull it out via substr parsing
    -- --------------------------------------------------------------------------------------------
    v_error_id := to_number(substr(v_logger_logs_rt.text,
                                   (v_1st_pipe_position + 1),
                                   v_errorID_substr_length)
                            );

    -- --------------------------------------------------------------------------------------------
    -- Get the length of the 2nd chunk (from the 2nd pipe to the 3rd) in order to be able to get
    --  the error text
    -- --------------------------------------------------------------------------------------------
    v_errorText_substr_length := (v_3rd_pipe_position - 1) - v_2nd_pipe_position;

    -- --------------------------------------------------------------------------------------------
    -- Pull the error text from the string
    -- --------------------------------------------------------------------------------------------
    v_error_text := substr(v_logger_logs_rt.text,v_2nd_pipe_position + 1,v_errorText_substr_length);

    -- --------------------------------------------------------------------------------------------
    -- For logger records that are logged through the procedure - 
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
                                     p_error_text => v_error_text);

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
  v_1st_curly_position             integer;
  v_sqlerrm                        varchar2(1000);
                               
  begin

    -- ---------------------------------------------------------------------------------------------------
    -- sqlerrm format: 'ORA-20723: {"loggerID":143,"errorID":-1476,"errorText":"divisor is equal to zero"}
    -- ---------------------------------------------------------------------------------------------------
    dbms_output.put_line('p_sqlerrm = '||p_sqlerrm);

    v_1st_curly_position := instr(p_sqlerrm,'{',1,1);

    dbms_output.put_line('v_1st_curly_position = '||v_1st_curly_position);

    v_sqlerrm := substr(p_sqlerrm,v_1st_curly_position);

    dbms_output.put_line('v_sqlerrm = '||v_sqlerrm);

    apex_json.parse(v_sqlerrm);

    -- --------------------------------------------------------------------------------------------
    -- Get loggerID and set value in record
    -- --------------------------------------------------------------------------------------------
    v_rec_error.logger_id := apex_json.get_number(p_path=>'loggerID');

    -- --------------------------------------------------------------------------------------------
    -- Get errorID and set value in record
    -- --------------------------------------------------------------------------------------------
    v_rec_error.error_id := apex_json.get_number(p_path=>'errorID');

    -- --------------------------------------------------------------------------------------------
    -- Get errorText and set value in record
    -- --------------------------------------------------------------------------------------------
--    v_rec_error.error_text := apex_json.get_varchar2(p_path=>'errorText');

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
  procedure raise_anticipated_exception (
    p_text                           in varchar2         default null,
    p_scope                          in varchar2         default null,
    p_extra                          in clob             default null,
    p_params                         in logger.tab_param default logger.gc_empty_tab_param,
    p_error_id                       in logger_error_lkup.error_id%type) AS

  /* Local Variables */
  v_error_id                       varchar2(100);

  /* Exceptions */
  e_null_error_id                  exception;

  begin

    if (p_error_id is null) then
      raise e_null_error_id;
    end if;
    
    v_error_id := ('|'||p_error_id||'|');

    logger.log_error(p_text => (v_error_id || p_text ||'|'),
                     p_scope => p_scope,
                     p_extra => p_extra,
                     p_params => p_params);

  exception
    when e_null_error_id 
      then raise_application_error(-20000,'p_error_id input parameter cannot be null, when using raise_anticipated_exception');

  end raise_anticipated_exception;

  -- ------------------------------------------------------------------------------------------------
  -- Proc uses logger.log_error along with plugin to raise an exception to the caller as well
  --  as log the error to the logger_logs table.  Allows for the logger unique ID to be passed to 
  --  the caller in the exception message as well as an optional persisted error message that is 
  --  defined in the PREDEFINED_ERROR_LKUP lookup table.  Both error message ID's (the unique logger 
  --   ID and the optional persistent lookup ID will start your exception message text using the 
  --   following consistent format: |logID:1234|errID:5678|
  -- ------------------------------------------------------------------------------------------------
  procedure raise_unanticipated_exception (
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
    
    v_sqlcode := ('|'||to_char(p_sqlcode)||'|');
    v_sqlerrm := substr(p_sqlerrm,(v_1st_colon_position + 2),512);

    logger.log_error(p_text => (v_sqlcode || v_sqlerrm ||'|'|| p_text),
                     p_scope => p_scope,
                     p_extra => p_extra,
                     p_params => p_params);

  exception
    when e_null_sqlcode 
      then raise_application_error(-20000,'p_sqlcode input parameter cannot be null, when using raise_unanticipated_exception');

    when e_null_sqlerrm 
      then raise_application_error(-20000,'p_sqlerrm input parameter cannot be null, when using raise_unanticipated_exception');

  end raise_unanticipated_exception;

end raiser;
/

begin

	update logger_prefs
	  set pref_value = 'raiser.logger_raiser_plugin'
	where 1=1
	  and pref_name = 'PLUGIN_FN_ERROR';
	
	commit;
	  
	begin logger_configure; end;

end;
/
