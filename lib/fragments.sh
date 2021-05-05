# global variables managing the state of the fragment manager. treat as private.
declare -A fragment_function_info                # maps a function name to a string with KEY=VALUEs information about the defining fragment
declare -i initialize_fragment_manager_counter=0 # how many times has the fragment manager initialized?
declare -A defined_hook_point_functions          # keeps a map of hook point functions that were defined and their fragment info
declare -A hook_point_function_trace_sources     # keeps a map of hook point functions that were actually called and their source
declare -A hook_point_function_trace_lines       # keeps a map of hook point functions that were actually called and their source
# configuration.
export DEBUG_HOOKS=no # set to yes to log every hook function called to the main build log

# This is a helper function for calling hooks.
# It follows the pattern long used in the codebase for hook-like behaviour:
#    [[ $(type -t name_of_hook_function) == function ]] && name_of_hook_function
# but with the following added behaviors:
# 1) it allows for many arguments, and will treat each as a hook point.
#    this allows for easily kept backwards compatibility when renaming hooks, for example.
# 2) it will read the stdin and assume it's (Markdown) documentation for the hook point.
#    combined with heredoc in the call site, it allows for "inline" documentation about the hook
# notice: this is not involved in how the hook functions came to be. read below for that.
call_hook_point() {
	# First, consume the stdin and write metadata about the call.
	write_hook_point_metadata "$@" || true

	# Then a sanity check, hook points should only be invoked after the manager has initialized.
	if [[ ${initialize_fragment_manager_counter} -lt 1 ]]; then
		display_alert "Fragment problem" "Call to call_hook_point() (in ${BASH_SOURCE[1]- $(get_fragment_hook_stracktrace "${BASH_SOURCE[*]}" "${BASH_LINENO[*]}")}) before fragment manager is initialized." "err"
	fi

	# With DEBUG_HOOKS, log the hook call. Users might be wondering what/when is a good hook point to use, and this is visual aid.
	[[ "${DEBUG_HOOKS}" == "yes" ]] &&
		display_alert "Hook point '${1}' being called from" "$(get_fragment_hook_stracktrace "${BASH_SOURCE[*]}" "${BASH_LINENO[*]}")" ""

	# Then call the hooks, if they are defined.
	for hook_name in "$@"; do
		echo "-- hook being called: ${hook_name}" >>"${FRAGMENT_MANAGER_LOG_FILE}"
		# shellcheck disable=SC2086
		[[ $(type -t ${hook_name}) == function ]] && { ${hook_name}; }
	done
}

# what this does is a lot of bash mumbo-jumbo to find all board-,family-,config- or user-defined hook points.
# the meat of this is 'compgen -A function', which is bash builtin that lists all defined functions.
# it will then compose a full hook point (function) that calls all the implementing hooks.
# this centralized function will then be called by the regular Armbian build system, which is oblivious to how
# it came to be. (although it is encouraged to call hook points via call_hook_point() above)
# to avoid hard coding the list of hook-points (eg: user_config, image_tweaks_pre_customize, etc) we use
# a marker in the function names, namely "__" (two underscores) to determine the hook point.
initialize_fragment_manager() {
	# before starting, auto-add fragments specified (eg, on the command-line) via the ADD_FRAGMENTS env var. Do it only once.
	[[ ${initialize_fragment_manager_counter} -lt 1 ]] && [[ "${ADD_FRAGMENTS}" != "" ]] && {
		local auto_fragment
		for auto_fragment in $(echo "${ADD_FRAGMENTS}" | tr "," " "); do
			ADD_FRAGMENT_TRACE_HINT="CMDLINE -> " add_fragment "${auto_fragment}"
		done
	}

	# This marks the manager as initialized, no more fragments are allowed to load after this.
	export initialize_fragment_manager_counter=$((initialize_fragment_manager_counter + 1))

	# log whats happening.
	echo "-- initialize_fragment_manager() called." >>"${FRAGMENT_MANAGER_LOG_FILE}"

	# this is the all-important separator.
	local hook_fragment_delimiter="__"

	# list all defined functions. filter only the ones that have the delimiter. get only the part before the delimiter.
	# sort them, and make them unique. the sorting is required for uniq to work, and does not affect the ordering of execution.
	# get them on a single line, space separated.
	local all_hook_points
	all_hook_points="$(compgen -A function | grep "${hook_fragment_delimiter}" | awk -F "${hook_fragment_delimiter}" '{print $1}' | sort | uniq | xargs echo -n)"

	declare -i hook_points_counter=0 hook_functions_counter=0 hook_point_functions_counter=0

	local FUNCTION_SORT_OPTIONS="--general-numeric-sort --ignore-case" #  --random-sort could be used to introduce chaos
	local hook_point=""
	# now loop over the hook_points.
	for hook_point in ${all_hook_points}; do
		echo "-- hook_point ${hook_point}" >>"${FRAGMENT_MANAGER_LOG_FILE}"

		# check if the hook point is already defined as a function.
		# that can happen for example with user_config(), that can be implemented itself directly by a userpatches config.
		# for now, just warn, but we could devise a way to actually integrate it in the call list.
		# or: advise the user to rename their user_config() function to something like user_config__make_it_awesome()
		local existing_hook_point_function
		existing_hook_point_function="$(compgen -A function | grep "^${hook_point}\$")"
		if [[ "${existing_hook_point_function}" == "${hook_point}" ]]; then
			echo "--- hook_point_functions (final sorted realnames): ${hook_point_functions}" >>"${FRAGMENT_MANAGER_LOG_FILE}"
			display_alert "Fragment conflict" "function ${hook_point} already defined! ignoring functions: $(compgen -A function | grep "^${hook_point}${hook_fragment_delimiter}")" "wrn"
			continue
		fi

		# for each hook_point, obtain the list of implementing functions.
		# the sort order here is (very) relevant, since it determines final execution order.
		# so the name of the functions actually determine the ordering.
		local hook_point_functions hook_point_functions_pre_sort hook_point_functions_sorted_by_sort_id

		# Sorting. Multiple fragments (or even the same fragment twice) can implement the same hook point
		# as long as they have different function names (the part after the double underscore __).
		# the order those will be called depends on the name; eg:
		# 'hook_point__033_be_awesome()' would be caller sooner than 'hook_point__799_be_even_more_awesome()'
		# independent from where they were defined or in which order the fragments containing them were added.
		# since requiring specific ordering could hamper portability, we reward fragment authors who
		# don't mind ordering for writing just: 'hook_point__be_just_awesome()' which is automatically rewritten
		# as 'hook_point__500_be_just_awesome()'.
		# fragment authors who care about ordering can use the 3-digit number, and use the context variables
		# HOOK_ORDER and HOOK_POINT_TOTAL_FUNCS to confirm in which order they're being run.

		# gather the real names of the functions (after the delimiter).
		hook_point_functions_pre_sort="$(compgen -A function | grep "^${hook_point}${hook_fragment_delimiter}" | awk -F "${hook_fragment_delimiter}" '{print $2}' | xargs echo -n)"
		echo "--- hook_point_functions_pre_sort: ${hook_point_functions_pre_sort}" >>"${FRAGMENT_MANAGER_LOG_FILE}"

		# add "500_" to the names of function that do NOT start with a number.
		# keep a reference from the new names to the old names (we'll sort on the new, but invoke the old)
		declare -A hook_point_functions_sortname_to_realname
		declare -A hook_point_functions_realname_to_sortname
		for hook_point_function_realname in ${hook_point_functions_pre_sort}; do
			local sort_id="${hook_point_function_realname}"
			[[ ! $sort_id =~ ^[0-9] ]] && sort_id="500_${sort_id}"
			hook_point_functions_sortname_to_realname[${sort_id}]="${hook_point_function_realname}"
			hook_point_functions_realname_to_sortname[${hook_point_function_realname}]="${sort_id}"
		done

		# actually sort the sort_id's...
		# shellcheck disable=SC2086
		hook_point_functions_sorted_by_sort_id="$(echo "${hook_point_functions_realname_to_sortname[*]}" | tr " " "\n" | LC_ALL=C sort ${FUNCTION_SORT_OPTIONS} | xargs echo -n)"
		echo "--- hook_point_functions_sorted_by_sort_id: ${hook_point_functions_sorted_by_sort_id}" >>"${FRAGMENT_MANAGER_LOG_FILE}"

		# then map back to the real names, keeping the order..
		hook_point_functions=""
		for hook_point_function_sortname in ${hook_point_functions_sorted_by_sort_id}; do
			hook_point_functions="${hook_point_functions} ${hook_point_functions_sortname_to_realname[${hook_point_function_sortname}]}"
		done
		# shellcheck disable=SC2086
		hook_point_functions="$(echo -n ${hook_point_functions})"
		echo "--- hook_point_functions (final sorted realnames): ${hook_point_functions}" >>"${FRAGMENT_MANAGER_LOG_FILE}"

		hook_point_functions_counter=0
		hook_points_counter=$((hook_points_counter + 1))

		# determine the variables we'll pass to the hook function during execution.
		# this helps the fragment author create fragments that are portable between userpatches and official Armbian.
		# shellcheck disable=SC2089
		local common_function_vars="HOOK_POINT=\"${hook_point}\""

		# loop over the functions for this hook_point (keep a total for the hook point and a grand running total)
		for hook_point_function in ${hook_point_functions}; do
			hook_point_functions_counter=$((hook_point_functions_counter + 1))
			hook_functions_counter=$((hook_functions_counter + 1))
		done
		common_function_vars="${common_function_vars} HOOK_POINT_TOTAL_FUNCS=\"${hook_point_functions_counter}\""

		echo "-- hook_point: ${hook_point} will run ${hook_point_functions_counter} functions: ${hook_point_functions}" >>"${FRAGMENT_MANAGER_LOG_FILE}"
		local temp_source_file_for_hook_point="${SRC}"/.tmp/fragment_function_definition.sh

		hook_point_functions_loop_counter=0

		# now compose a function definition. notice the heredoc. it will be written to tmp file, logged, then sourced.
		# theres a lot of opportunities here, but for now I keep it simple:
		# - execute functions in the order defined by ${hook_point_functions} above
		# - define call-specific environment variables, to help fragment authors to write portable fragments (eg: FRAGMENT_DIR)
		cat <<FUNCTION_DEFINITION_HEADER >"${temp_source_file_for_hook_point}"
		${hook_point}() {
			echo "*** Fragment-managed hook starting '${hook_point}': will run ${hook_point_functions_counter} functions: '${hook_point_functions}'" >>"\${FRAGMENT_MANAGER_LOG_FILE}"
FUNCTION_DEFINITION_HEADER

		for hook_point_function in ${hook_point_functions}; do
			hook_point_functions_loop_counter=$((hook_point_functions_loop_counter + 1))

			# store the full name in a hash, so we can track which were actually called later.
			defined_hook_point_functions["${hook_point}${hook_fragment_delimiter}${hook_point_function}"]="DEFINED=yes ${fragment_function_info["${hook_point}${hook_fragment_delimiter}${hook_point_function}"]}"

			# prepare the call context
			local hook_point_function_variables="${common_function_vars}" # start with common vars... (eg: HOOK_POINT_TOTAL_FUNCS)
			# add the contextual fragment info for the function (eg, FRAGMENT_DIR)
			hook_point_function_variables="${hook_point_function_variables} ${fragment_function_info["${hook_point}${hook_fragment_delimiter}${hook_point_function}"]}"
			# add the current execution counter, so the fragment author can know in which order it is being actually called
			hook_point_function_variables="${hook_point_function_variables} HOOK_ORDER=\"${hook_point_functions_loop_counter}\""

			# add it to our (not the call site!) environment. if we export those in the call site, the stack is corrupted.
			local "${hook_point_function_variables}"

			# output the call, passing arguments, and also logging the output to the fragments log.
			# attention: don't pipe here (eg, capture output), otherwise hook function cant modify the environment (which is mostly the point)
			# @TODO: better error handling. we have a good opportunity to 'set -e' here, and 'set +e' after, so that fragment authors are encouraged to write error-free handling code
			cat <<FUNCTION_DEFINITION_CALLSITE >>"${temp_source_file_for_hook_point}"
			hook_point_function_trace_sources["${hook_point}${hook_fragment_delimiter}${hook_point_function}"]="\${BASH_SOURCE[*]}"
			hook_point_function_trace_lines["${hook_point}${hook_fragment_delimiter}${hook_point_function}"]="\${BASH_LINENO[*]}"
			[[ "\${DEBUG_HOOKS}" == "yes" ]] && display_alert "Hook ${hook_point}" "${hook_point_functions_loop_counter}/${hook_point_functions_counter} (frag:${FRAGMENT:-built-in}) ${hook_point_function}" ""
			echo "*** *** Fragment-managed hook starting ${hook_point_functions_loop_counter}/${hook_point_functions_counter} '${hook_point}${hook_fragment_delimiter}${hook_point_function}':" >>"\${FRAGMENT_MANAGER_LOG_FILE}"
			${hook_point_function_variables} ${hook_point}${hook_fragment_delimiter}${hook_point_function} "\$@"
			echo "*** *** Fragment-managed hook finished ${hook_point_functions_loop_counter}/${hook_point_functions_counter} '${hook_point}${hook_fragment_delimiter}${hook_point_function}':" >>"\${FRAGMENT_MANAGER_LOG_FILE}"
FUNCTION_DEFINITION_CALLSITE

			# unset fragment vars for the next loop.
			unset FRAGMENT FRAGMENT_DIR FRAGMENT_FILE FRAGMENT_ADDED_BY
		done

		cat <<FUNCTION_DEFINITION_FOOTER >>"${temp_source_file_for_hook_point}"
			echo "*** Fragment-managed hook ending '${hook_point}': completed." >>"\${FRAGMENT_MANAGER_LOG_FILE}"
		} # end ${hook_point}() function
FUNCTION_DEFINITION_FOOTER

		# unsets, lest the next loop inherits them
		unset hook_point_functions hook_point_functions_sortname_to_realname hook_point_functions_realname_to_sortname

		# log what was produced in our own debug logfile
		cat "${temp_source_file_for_hook_point}" >>"${FRAGMENT_MANAGER_LOG_FILE}"

		# source the generated function.
		# shellcheck disable=SC1090
		source "${temp_source_file_for_hook_point}"

		rm -f "${temp_source_file_for_hook_point}"
	done

	# Dont show any output until we have more than 1 hook function (we implement one already, below)
	[[ ${hook_functions_counter} -gt 0 ]] &&
		display_alert "Fragment manager" "processed ${hook_points_counter} hook points and ${hook_functions_counter} hook functions" "info" | tee -a "${FRAGMENT_MANAGER_LOG_FILE}"
}

# why not eat our own dog food?
# process everything that happened during fragment related activities
# and write it to the log. also, move the log from the .tmp dir to its
# final location. this will make run_after_build() "hot" (eg, emit warnings)
run_after_build__999_finish_fragment_manager() {
	# export these maps, so the hook can access them and produce useful stuff.
	export defined_hook_point_functions hook_point_function_trace_sources

	# eat our own dog food, pt2.
	call_hook_point "fragment_metadata_ready" <<'FRAGMENT_METADATA_READY'
*meta-Meta time!*
Implement this hook to work with/on the meta-data made available by the fragment manager.
Interesting stuff to process:
- `"${FRAGMENT_MANAGER_TMP_DIR}/hook_point_calls.txt"` contains a list of all hook points called, in order.
- For each hook_point in the list, more files will have metadata about that hook point.
  - `${FRAGMENT_MANAGER_TMP_DIR}/hook_point.orig.md` contains the hook documentation at the call site (inline docs), hopefully in Markdown format.
  - `${FRAGMENT_MANAGER_TMP_DIR}/hook_point.compat` contains the compatibility names for the hooks.
  - `${FRAGMENT_MANAGER_TMP_DIR}/hook_point.exports` contains _exported_ environment variables.
  - `${FRAGMENT_MANAGER_TMP_DIR}/hook_point.vars` contains _all_ environment variables.
- `${defined_hook_point_functions}` is a map of _all_ the defined hook point functions and their fragment information.
- `${hook_point_function_trace_sources}` is a map of all the hook point functions _that were really called during the build_ and their BASH_SOURCE information.
- `${hook_point_function_trace_lines}` is the same, but BASH_LINENO info.
After this hook is done, the `${FRAGMENT_MANAGER_TMP_DIR}` will be removed.
FRAGMENT_METADATA_READY

	# Cleanup. Leave no trace...
	[[ -d "${FRAGMENT_MANAGER_TMP_DIR}" ]] && rm -rf "${FRAGMENT_MANAGER_TMP_DIR}"

	# Move temporary log file over to final destination, and start writing to it instead (although 999 is pretty late in the game)
	mv "${FRAGMENT_MANAGER_LOG_FILE}" "${DEST}"/debug/
	export FRAGMENT_MANAGER_LOG_FILE="${DEST}"/debug/fragments.log
}

# This is called by call_hook_point(). To say the truth, this should be in a fragment. But then it gets too meta for anyone's head.
write_hook_point_metadata() {
	local main_hook_point_name="$1"

	cat - >"${FRAGMENT_MANAGER_TMP_DIR}/${main_hook_point_name}.orig.md" # Write the hook point documentation received via stdin to a tmp file for later processing.
	shift
	echo -n "$@" >"${FRAGMENT_MANAGER_TMP_DIR}/${main_hook_point_name}.compat"       # log the 2nd+ arguments too (those are the alternative/compatibility names), separate file.
	compgen -A export >"${FRAGMENT_MANAGER_TMP_DIR}/${main_hook_point_name}.exports" # capture the exported env vars.
	compgen -A variable >"${FRAGMENT_MANAGER_TMP_DIR}/${main_hook_point_name}.vars"  # capture all env vars.

	# add to the list of hook points called, in order.
	echo "${main_hook_point_name}" >>"${FRAGMENT_MANAGER_TMP_DIR}/hook_point_calls.txt"
}

# Helper function, to get clean "stack traces" that do not include the hook/fragment infrastructure code.
get_fragment_hook_stracktrace() {
	local sources_str="$1" # Give this ${BASH_SOURCE[*]} - expanded
	local lines_str="$2"   # And this # Give this ${BASH_LINENO[*]} - expanded
	local sources lines index final_stack=""
	IFS=' ' read -r -a sources <<<"${sources_str}"
	IFS=' ' read -r -a lines <<<"${lines_str}"
	for index in "${!sources[@]}"; do
		local source="${sources[index]}" line="${lines[index]}"
		# skip fragment infrastructure sources, these only pollute the trace and add no insight to users
		[[ ${source} == */.tmp/fragment_function_definition.sh ]] && continue
		[[ ${source} == *lib/fragments.sh ]] && continue
		[[ ${source} == */compile.sh ]] && continue
		# relativize the source, otherwise too long to display
		source="${source#"${SRC}/"}"
		# remove 'lib/'. hope this is not too confusing.
		source="${source#"lib/"}"
		# add to the list
		arrow="$([[ "$final_stack" != "" ]] && echo " -> ")"
		final_stack="${source}:${line} ${arrow} ${final_stack} "
	done
	# output the result, no newline
	echo -n $final_stack
}

# can be called by board, family, config or user to make sure a fragment is included.
# single argument is the fragment name.
# will look for it in /userpatches/fragments first.
# if not found there will look in /fragments
# if not found will throw and abort compilation (or will it? no set -e no this codebase in general)
add_fragment() {
	local fragment_name="$1"
	local fragment_dir fragment_file fragment_file_in_dir fragment_floating_file stacktrace

	# capture the stack leading to this, possibly with a hint in front.
	stacktrace="${ADD_FRAGMENT_TRACE_HINT}$(get_fragment_hook_stracktrace "${BASH_SOURCE[*]}" "${BASH_LINENO[*]}")"

	# if DEBUG_HOOKS, output useful stack, so user can figure out which fragments are being added where
	[[ "${DEBUG_HOOKS}" == "yes" ]] &&
		display_alert "Fragment being added" "${fragment_name} :: added by ${stacktrace}" ""

	# first a check, has the fragment manager already initialized? then it is too late to add_fragment(). bail.
	if [[ ${initialize_fragment_manager_counter} -gt 0 ]]; then
		echo "ERR: Fragment problem -- already initialized -- too late to add '${fragment_name}' (trace: ${stacktrace})" | tee -a "${FRAGMENT_MANAGER_LOG_FILE}"
		exit 2
	fi

	# there are many opportunities here. too many, actually. let userpatches override just some functions, etc.
	for fragment_base_path in "${SRC}/userpatches/fragments" "${SRC}/fragments"; do
		fragment_dir="${fragment_base_path}/${fragment_name}"
		fragment_file_in_dir="${fragment_dir}/${fragment_name}.sh"
		fragment_floating_file="${fragment_base_path}/${fragment_name}.sh"

		if [[ -d "${fragment_dir}" ]] && [[ -f "${fragment_file_in_dir}" ]]; then
			fragment_file="${fragment_file_in_dir}"
			break
		elif [[ -f "${fragment_floating_file}" ]]; then
			fragment_dir="${fragment_base_path}" # this is misleading. only directory-based fragments should have this.
			fragment_file="${fragment_floating_file}"
			break
		fi
	done

	# After that, we should either have fragment_file and fragment_dir, or throw.
	if [[ ! -f "${fragment_file}" ]]; then
		echo "ERR: Fragment problem -- cant find fragment '${fragment_name}' anywhere - called by ${BASH_SOURCE[1]}" | tee -a "${FRAGMENT_MANAGER_LOG_FILE}"
		return 1
	fi

	local before_function_list after_function_list new_function_list

	# store a list of existing functions at this point, before sourcing the fragment.
	before_function_list="$(compgen -A function)"

	# source the file. fragments are not supposed to do anything except export variables and define functions, so nothing should happen here.
	# there is no way to enforce it though.
	# we could punish the fragment authors who violate it by removing some essential variables temporarily from the environment during this source, and restore them later.
	# shellcheck disable=SC1090
	. "${fragment_file}"

	# get a new list of functions after sourcing the fragment
	after_function_list="$(compgen -A function)"

	# compare before and after, thus getting the functions defined by the fragment.
	# comm is oldskool. we like it. go "man comm" to understand -13 below
	new_function_list="$(comm -13 <(echo "$before_function_list") <(echo "$after_function_list"))"

	# iterate over defined functions, store them in global associative array fragment_function_info
	for newly_defined_function in ${new_function_list}; do
		echo "fragment: ${fragment_name} defined function ${newly_defined_function}" >>"${FRAGMENT_MANAGER_LOG_FILE}"
		fragment_function_info["${newly_defined_function}"]="FRAGMENT=\"${fragment_name}\" FRAGMENT_DIR=\"${fragment_dir}\" FRAGMENT_FILE=\"${fragment_file}\" FRAGMENT_ADDED_BY=\"${stacktrace}\""
	done

	# Always output to the log
	echo "Fragment added: '${fragment_name}': from ${fragment_file} - added by: '${stacktrace}'" >>"${FRAGMENT_MANAGER_LOG_FILE}"

}

# For the insanity above to (eventually) make sense to anyone we need logging. Unfortunately,
# this runs super early (from compile.sh), and its too early to write to /output/debug.
export FRAGMENT_MANAGER_TMP_DIR="${SRC}/.tmp/.fragments"
export FRAGMENT_MANAGER_LOG_FILE="${SRC}/.tmp/fragments.log"
mkdir -p "${SRC}"/.tmp "${FRAGMENT_MANAGER_TMP_DIR}"
echo -n "" >"${FRAGMENT_MANAGER_TMP_DIR}/hook_point_calls.txt"

# globally initialize the fragments log.
echo "-- lib/fragments.sh included. logs will be below, followed by the debug generated by the initialize_fragment_manager() function." >"${FRAGMENT_MANAGER_LOG_FILE}"
