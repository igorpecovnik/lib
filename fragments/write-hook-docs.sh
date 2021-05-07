## Hooks
function fragment_metadata_ready__499_display_docs_generation_start_info() {
	display_alert "Generating hook documentation and sample fragment"
}

function fragment_metadata_ready__docs_markdown() {
	generate_markdown_docs_to_stdout >"${DEST}/debug/hooks.auto.docs.md"
}

function fragment_metadata_ready__docs_sample_fragment() {
	mkdir -p "${SRC}/userpatches/fragments"
	generate_sample_fragment_to_stdout >"${SRC}/userpatches/fragments/sample-fragment.sh"
}

## Internal functions

### Common stuff
function read_common_data() {
	export HOOK_POINT_CALLS_COUNT=$(wc -l <"${FRAGMENT_MANAGER_TMP_DIR}/hook_point_calls.txt")
	export HOOK_POINT_CALLS_UNIQUE_COUNT=$(sort <"${FRAGMENT_MANAGER_TMP_DIR}/hook_point_calls.txt" | uniq | wc -l)
	export HOOK_POINTS_WITH_MULTIPLE_CALLS=""

	# Read the hook_points (main, official names) from the hook point ordering file.
	export ALL_HOOK_POINT_CALLS=$(xargs echo -n <"${FRAGMENT_MANAGER_TMP_DIR}/hook_point_calls.txt")
}

function loop_over_hook_points_and_call() {
	local callback="$1"
	HOOK_POINT_COUNTER=0
	for one_hook_point in ${ALL_HOOK_POINT_CALLS}; do
		export HOOK_POINT_COUNTER=$((HOOK_POINT_COUNTER + 1))
		export HOOK_POINT="${one_hook_point}"
		export MARKDOWN_HEAD="$(head -1 "${FRAGMENT_MANAGER_TMP_DIR}/${one_hook_point}.orig.md")"
		export MARKDOWN_BODY="$(tail -n +2 "${FRAGMENT_MANAGER_TMP_DIR}/${one_hook_point}.orig.md")"
		export COMPATIBILITY_NAMES="$(xargs echo -n <"${FRAGMENT_MANAGER_TMP_DIR}/${one_hook_point}.compat")"
		${callback}
	done
}

## Markdown stuff
function generate_markdown_docs_to_stdout() {
	read_common_data
	cat <<MASTER_HEADER
# Armbian build system extensibility documentation
- This documentation is auto-generated.
MASTER_HEADER

	[[ $HOOK_POINT_CALLS_COUNT -gt $HOOK_POINT_CALLS_UNIQUE_COUNT ]] && {
		# Some hook points were called multiple times, determine which.
		HOOK_POINTS_WITH_MULTIPLE_CALLS=$(comm -13 <(sort <"${FRAGMENT_MANAGER_TMP_DIR}/hook_point_calls.txt" | uniq) <(sort <"${FRAGMENT_MANAGER_TMP_DIR}/hook_point_calls.txt") | sort | uniq | xargs echo -n)

		cat <<MULTIPLE_CALLS_WARNING
- *Important:* The following hook points where called multiple times during the documentation generation. This can be indicative of a bug in the build system. Please check the sources for the invocation of the following hooks: \`${HOOK_POINTS_WITH_MULTIPLE_CALLS}\`.
MULTIPLE_CALLS_WARNING

	}

	cat <<PRE_HOOKS_HEADER
## Hooks
- Hooks are listed in the order they are called.
PRE_HOOKS_HEADER

	loop_over_hook_points_and_call "generate_markdown_one_hook_point_to_stdout"

	cat <<MASTER_FOOTER
------------------------------------------------------------------------------------------
MASTER_FOOTER

}

function generate_markdown_one_hook_point_to_stdout() {
	# Hook name in 3rd level title, first line of description in a blockquote.
	# The rest in a normal block.
	cat <<HOOK_DOCS
### \`${one_hook_point}\`
> ${MARKDOWN_HEAD}

${MARKDOWN_BODY}

HOOK_DOCS

	[[ "${COMPATIBILITY_NAMES}" != "" ]] && {
		echo -e "\n\nAlso known as (for backwards compatibility only):"
		for old_name in ${COMPATIBILITY_NAMES}; do
			echo "- \`${old_name}\`"
		done
	}

	echo ""
}

## Bash sample fragment stuff
generate_sample_fragment_to_stdout() {
	read_common_data
	cat <<HEADER
# Sample Armbian build system fragment with all hooks.
# This file is auto-generated from the build system.
# Please, always use the latest available version of this file as a starting point for your own fragments.
# Read more about the build extensibility system at https://todo

HEADER

	loop_over_hook_points_and_call "generate_bash_sample_for_hook_point"
}

generate_bash_sample_for_hook_point() {
	# Include the markdown documentation as a comment.
	# Right now clean it up naively (remove backticks, mostly) but we could pipe through stuff to get better plaintext. (pandoc is a 155mb binary FYI)
	local COMMENT_HEAD="#### $(echo "${MARKDOWN_HEAD}" | tr '`' '"')"
	# shellcheck disable=SC2001
	local COMMENT_BODY="$(echo "${MARKDOWN_BODY}" | tr '`' '"' | sed -e 's/^/###  /')"

	local bonus=""
	[[ "${HOOK_POINT_COUNTER}" == "1" ]] && bonus="$(echo -e "\n\texport PROGRESS_DISPLAY=verysilent # Example: export a variable. This one silences the built.")"

	cat <<SAMPLE_BASH_CODE
${COMMENT_HEAD}
${COMMENT_BODY}
${HOOK_POINT}__be_more_awesome() {
	# @TODO: Here goes your code. As an example, here's a call to display_message. Bask in its colorful glory.
	display_alert "AWESOME Sample hook ${HOOK_POINT_COUNTER}/${HOOK_POINT_CALLS_COUNT}" "making '${HOOK_POINT}' more awesome" "info"${bonus}
	# @TODO: Please also remember to rename this function, but preserve the "${HOOK_POINT}__" prefix.
} # end of function ${HOOK_POINT}__be_more_awesome()

SAMPLE_BASH_CODE
}

## For later:
## 	# Keep track of the variables.
## 	local PREVIOUS_VARS=""
## 	#export EXPORTED_VARS="$(cat "${FRAGMENT_MANAGER_TMP_DIR}/${one_hook_point}.exports" | xargs echo -n)"
## 	export ALL_VARS="$(cat "${FRAGMENT_MANAGER_TMP_DIR}/${one_hook_point}.vars")"
## 	export NEW_VARS=""
## 	[[ "${PREVIOUS_VARS}" != "" ]] && {
## 		NEW_VARS=$(comm -3 <(echo "${PREVIOUS_VARS}") <(echo "${ALL_VARS}") | sort | uniq | xargs echo -n)
## 	}
## 	export PREVIOUS_VARS="${ALL_VARS}"
## 	echo "Hook ${one_hook_point} New vars: ${NEW_VARS}"
##
## 	cat <<EOD
## -- one_hook_point: ${one_hook_point}
##    EXPORTED_VARS: ${EXPORTED_VARS}
##    ALL_VARS: ${ALL_VARS}
## EOD

## ## Commandline calling.
## export FRAGMENT_MANAGER_TMP_DIR="$(pwd)/.tmp/.fragments"
## fragment_metadata_ready__docs_sample_fragment
## fragment_metadata_ready__docs_markdown
