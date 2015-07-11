create or replace PACKAGE raiser AS

--  Ver#    ---Date---  --- Done-By ---     ----- What-Was-Done -----------------------------------
--  1.00    22 Apr 2015 Dan Gillis          New Package
--
--  Purpose:
--  1. Package allows you to raise an exception leveraging all of the logger functionality (through
--       the logger PLUGIN_FN_ERROR plugin) as well as raise your own unique exception ID.  This
--       allows you not to be constrained by Oracle's -70000 to 70999 range - you define your own!
--       There are examples of how to use the package at PUT GITHUB ADDRESS HERE, as well as how to 
--       raise and catch an exception
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
  -- Function takes in the SQLERRM from a thrown exception (using one of the raiser.rle procs)
  -- as a varchar2 and parses it based on the consistent format used by raiser.rle
  -- ----------------------------------------------------------------------------------------------
  function getErrorDetails (p_sqlerrm in varchar2) return error_rt;

  -- ----------------------------------------------------------------------------------------------
  -- Proc uses logger.log_error along with plugin to raise an exception to the caller as well
  --  as log the error to the logger_logs table.  Allows for the logger unique ID to be passed to 
  --  the caller in the exception message as well as an optional persisted error message that is 
  --  defined in the PREDEFINED_ERROR_LKUP lookup table.  Both error message ID's (the unique logger 
  --   ID and the optional persistent lookup ID will start your exception message text using the 
  --   following consistent format: |logID:1234|errID:5678|
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
  --   ID and the optional persistent lookup ID will start your exception message text using the 
  --   following consistent format: |logID:1234|errID:5678|
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
create or replace PACKAGE BODY raiser AS

--  Ver#    ---Date---  --- Done-By ---     ----- What-Was-Done -----------------------------------
--  1.00    22 Apr 2015 Dan Gillis          New Package
--
--  Purpose:
--  1. Package to ...
--

  -- ------------------------------------------------------------------------------------------------
  -- PRIVATE proc to insert error data into xref table 
  -- ------------------------------------------------------------------------------------------------
  procedure insert_logger_error_xref (p_logger_error_xref_rt IN logger_error_xref%rowtype) AS
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
  end;

  -- ----------------------------------------------------------------------------------------------
  -- proc is called by the logger.log_error PLUGIN_FN_ERROR plugin
  -- ----------------------------------------------------------------------------------------------
  procedure logger_raiser_plugin (p_rec in logger.rec_logger_log) AS
  
  /* Local Variables */
  v_error_text  varchar2(1000);

  /* Record Types */
  v_logger_logs_rt                 logger_logs%rowtype;
  v_logger_error_xref_rt           logger_error_xref%rowtype;

  /* Variables */
  v_error_id                       integer;
  v_1st_pipe_position              integer;
  v_2nd_pipe_position              integer;
  v_substr_length                  integer;
  v_text_minus_error_id            varchar2(1000);
  
  begin
    -- --------------------------------------------------------------------------------------------
    -- Get logger_logs record - eventually this step will be eliminated as the full logger_logs 
    --   record type will be passed through as part of Logger enhancement #102
    -- --------------------------------------------------------------------------------------------
    select *
      into v_logger_logs_rt
      from logger_logs
     where id = p_rec.id;

    v_1st_pipe_position := instr(v_logger_logs_rt.text,'|',1,1);
    v_2nd_pipe_position := instr(v_logger_logs_rt.text,'|',1,2);
    v_substr_length := (v_2nd_pipe_position - 1) - v_1st_pipe_position;
    v_text_minus_error_id := substr(v_logger_logs_rt.text,v_2nd_pipe_position + 1);

    -- --------------------------------------------------------------------------------------------
    -- Parse error ID form the logger_logs table - perhaps someday, we can add an error_id column
    --  to logger_logs, but until then, I have to bake the error id somewhere into the existing 
    --  data structure and pull it out via substr parsing
    -- --------------------------------------------------------------------------------------------
    v_error_id := to_number(substr(v_logger_logs_rt.text,(v_1st_pipe_position + 1),v_substr_length));

    -- --------------------------------------------------------------------------------------------
    -- For logger records that are logged through the rle procedure - 
    -- --------------------------------------------------------------------------------------------
    v_logger_error_xref_rt.logger_id := p_rec.id;
    v_logger_error_xref_rt.error_id := v_error_id;
    v_logger_error_xref_rt.create_user_id := v_logger_logs_rt.user_name;
    v_logger_error_xref_rt.create_date := v_logger_logs_rt.time_stamp;
    v_logger_error_xref_rt.update_user_id := v_logger_logs_rt.user_name;
    v_logger_error_xref_rt.update_date := v_logger_logs_rt.time_stamp;
--    dbms_output.put_line('Predefined Error: |logID:'||p_rec.id||'|errID:'||v_error_id||'|'||v_text_minus_error_id);
    insert_logger_error_xref(p_logger_error_xref_rt => v_logger_error_xref_rt);
    commit;
    raise_application_error(-20723,'|logID:'||p_rec.id||'|errID:'||v_error_id||'|'||v_text_minus_error_id);

  end logger_raiser_plugin;

  -- ---------------------------------------------------------------------------------------------
  -- Function takes in the SQLERRM from a thrown exception (using the raiser.rle proc)
  -- as a varchar2 and parses it based on the consistent format used by raiser.rle
  -- ---------------------------------------------------------------------------------------------
  FUNCTION getErrorDetails (p_sqlerrm in varchar2) return error_rt AS

  /* Record Type */
  v_rec_error                      error_rt;
                               
  begin
    dbms_output.put_line('p_sqlerrm = '||p_sqlerrm);

    v_rec_error.logger_id := substr(p_sqlerrm,instr(p_sqlerrm,'|',1,1)+7,instr(p_sqlerrm,'|',1,2)-instr(p_sqlerrm,'|',1,1)-7);
    dbms_output.put_line('logger_id = '||v_rec_error.logger_id);

    begin
      v_rec_error.error_id := substr(p_sqlerrm,instr(p_sqlerrm,'|',1,2)+7,instr(p_sqlerrm,'|',1,3)-instr(p_sqlerrm,'|',1,2)-7);
      dbms_output.put_line('error_id = '||v_rec_error.error_id);
    exception
      when value_error
        then
          v_rec_error.error_id := null;
          dbms_output.put_line('error_id (null) = '||v_rec_error.error_id);          
    end;

    v_rec_error.error_text := substr(p_sqlerrm,instr(p_sqlerrm,'|',-1,1)+1);
    dbms_output.put_line('error_text = '||v_rec_error.error_text);

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
    logger.log_error(p_text => (v_error_id || p_text),
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
    
    v_sqlcode := ('|'||to_char(p_sqlcode)||'|');
    v_sqlerrm := substr(p_sqlerrm,1,512);

    logger.log_error(p_text => (v_sqlcode || v_sqlerrm),
                     p_scope => p_scope,
                     p_extra => p_extra,
                     p_params => p_params);

  exception
    when e_null_sqlcode 
      then raise_application_error(-20000,'p_sqlcode input parameter cannot be null, when using raise_unanticipated_exception');

    when e_null_sqlerrm 
      then raise_application_error(-20000,'p_sqlerrm input parameter cannot be null, when using raise_unanticipated_exception');

  end raise_unanticipated_exception;
  /
  

end raiser;
