-module(exometer_probe).
-behaviour(gen_server).
-behaviour(exometer_entry).

% exometer_entry callb
-export([new/2,
	 delete/1,
	 get_value/1,
	 update/2,
	 reset/1,
	 sample/1,
	 setopts/2]).


%% gen_server callbacks
-export([init/1,
	 handle_call/3,
	 handle_cast/2,
	 handle_info/2,
	 terminate/2,
	 code_change/3]).

-include("exometer.hrl").

-record(st, {name,
	     module = undefined,
	     mod_state,
	     sample_timer,
	     sample_interval = 1000, %% msec
	     opts = []}).


%%
%% exometer_entry callbacks
%%
new(Name, Options) ->
    %% Extract the module to use.
    {value, {module, Module}, Opts1 } = lists:keytake(module, 1, Options), 

    %% ULF: Do we still need to run a separate registration module
    %% since we now work with pids?
    %% Start server and return pid as module state
%%    gen_server:start_link({via, exometer_reg, Name}, ?MODULE,
%%			  {Name, Module, Opts1}, []).
    gen_server:start_link(?MODULE, {Name, Module, Opts1}, []).

delete(Pid) when is_pid(Pid) ->
    gen_server:call(Pid, stop).
    

get_value(Pid) when is_pid(Pid) ->
    gen_server:call(Pid, get_value).

setopts(Options, Pid) when is_pid(Pid), is_list(Options) ->
    gen_server:call(Pid, {setopts, Options}).

update(Value, Pid) when is_pid(Pid) ->
    gen_server:call(Pid, {update, Value}).
	      
reset(Pid) when is_pid(Pid) ->
    gen_server:call(Pid, reset).
	      
sample(Pid) when is_pid(Pid) ->
    gen_server:call(Pid, sample).
	      

%% gen_server implementation
init({Name, Mod, Opts}) ->
    %% Extract the (exometer_entry callback) module to use
    St = process_opts(#st {name = Name, module = Mod}, Opts),

    %% Create a new state for the module
    io:format("exometer_probe(): St: ~p~n", [St]),
    case Mod:new(Name, St#st.opts) of
	{ok, ModSt} ->
	    %% Fire up the timer, save the new module state.
	    {ok, sample_(restart_timer(sample, St#st{ mod_state = ModSt }))};

	{error, Reason} ->
	    {error, Reason}
    end.

handle_call(stop, _From, St) ->
    {stop, terminated, ok, St};

handle_call(get_value, _From, St) ->
    %% Forward the call to the correct exometer_entry module
    %% (as specified by the 'module' option provided to new()).
    case (St#st.module):get_value(St#st.mod_state) of
	{ ok , Val, ModSt } -> {reply, { ok, Val, self() }, St#st { mod_state = ModSt }};
	{ error , Reason } -> {reply, { error, Reason }, St};
	_ -> { reply, badarg, St}
    end;


handle_call({setopts, Options}, _From, St) ->
    
    %% Process (and delete) local options.
    %% FIXME: Check for updated timer specs here and restart timer??
    NSt = process_opts(St, Options),
    
    case (NSt#st.module):setopts(NSt#st.opts, NSt#st.mod_state) of
	{ ok , ModSt } -> {reply, { ok, self() }, St#st { mod_state = ModSt }};
	{ error , Reason } -> {reply, { error, Reason }, St};
	_ -> { reply, badarg, St}
    end;

handle_call({update, Value}, _From, St) ->
    case (St#st.module):update(Value, St#st.mod_state) of
	{ ok , ModSt } -> {reply, { ok, self() }, St#st { mod_state = ModSt }};
	{ error , Reason } -> {reply, { error, Reason }, St};
	_ -> { reply, badarg, St}
    end;

handle_call(reset, _From, St) ->
    case (St#st.module):reset(St#st.mod_state) of
	{ ok , ModSt } -> {reply, { ok, self() }, St#st { mod_state = ModSt }};
	{ error , Reason } -> {reply, { error, Reason }, St};
	_ -> { reply, badarg, St}
    end;

handle_call(sample, _From, St) ->
    {reply, { ok, self() }, sample_(St)};

handle_call(_, _, St) ->
    {reply, error, St}.

handle_cast(_, St) ->
    {noreply, St}.

handle_info({timeout, TRef, sample}, #st{sample_timer = TRef} = St) ->
    {noreply, sample_(restart_timer(sample, St))};



handle_info(_, St) ->
    {noreply, St}.

terminate(_, _) ->
    ok.

code_change(From, #st{module = M, mod_state = ModSt} = St, Extra) ->
    case M:code_change(From, ModSt, Extra) of
	{ok, ModSt1} ->
	    {ok, St#st{mod_state = ModSt1}};
	Other ->
	    Other
    end.


sample_(#st{} = St) ->
    case (St#st.module):sample(St#st.mod_state) of
	{ ok, NModSt } ->
	    St#st { mod_state = NModSt };
	_ ->
	    St
    end.

%% ===================================================================

%% ULF:
%% Do we use this now that we have pids instead? The whole via 
%% setup feels a bit obsolete?
%%
%% call(Name, Req) ->
%%     gen_server:call({via, exometer_reg, Name}, Req).


restart_timer(sample, #st{sample_interval = Int} = St) ->
    St#st{sample_timer = start_timer(Int, sample)}.

start_timer(infinity, _) ->
    undefined;

start_timer(T, Msg) when is_integer(T), T >= 0, T =< 16#FFffFFff ->
    erlang:start_timer(T, self(), Msg).

process_opts(St, Options) ->
    lists:foldl(fun
		    %% Sample interval.
		    ({sample_interval, Val}, St1) -> St1#st { sample_interval = Val };

		    %% Unknown option, pass on to State options list, replacing
		    %% any earlier versions of the same option.
		    ({Opt, Val}, St1) ->
			St1#st { opts = [ {Opt, Val} | lists:keydelete(Opt, 1, St1#st.opts) ] }

		end, St, Options).











