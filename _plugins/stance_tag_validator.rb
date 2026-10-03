require "set"
require "date"
require_relative "stance_liquid_filters"

module StanceResponseValidator
  FILTERS_KEY = "stance_filters".freeze
  RESPONSES_KEY = "stance_responses".freeze
  QUESTIONS_KEY = "stance_questions".freeze
  TEAM_KEY = "stance_team".freeze

  RESPONSE_REQUIRED_FIELDS = %w[candidate_first_name candidate_last_name state race party question response].freeze
  QUESTION_REQUIRED_FIELDS = %w[id question tag].freeze
  COUNTY_RACE_RACE = "Local County Races [All]".freeze

  # A candidate who never answered has no question to answer and no answer text,
  # so these are not required on a row flagged `did_not_respond: true`.
  NON_RESPONDER_EXEMPT_FIELDS = %w[question response].freeze

  # Booleans that describe the candidate rather than the individual answer, and
  # that hide their rows from every view unless the matching checkbox is ticked.
  CANDIDATE_FLAG_FIELDS = %w[primary_candidate did_not_respond].freeze

  # Fields that describe the candidate rather than the individual answer. The
  # group-by-candidate cards and the generated per-candidate pages both render
  # these from whichever row happens to come first, so a candidate whose rows
  # disagree renders differently depending on YAML order — and splits into two
  # cards in the state explorer, which groups on exactly these values.
  CANDIDATE_CONSISTENT_FIELDS = %w[race district party county_race].freeze

  # A single validation failure. `row` is the 0-based position in the YAML list
  # (nil for whole-file problems), `subject` is the human name the row belongs to
  # (a candidate, a question id), `kind` is the short bucket the report groups
  # by, and `detail` is the offending value.
  Problem = Struct.new(:file, :row, :subject, :kind, :detail, keyword_init: true)

  # Printed once per `kind` group instead of repeating on every row.
  HINTS = {
    "invalid date" => "dates must be ISO 8601, e.g. 2026-07-13",
    "unknown race" => "allowed values: _data/stance_filters.yml → races",
    "unknown party" => "allowed values: _data/stance_filters.yml → parties",
    "unknown tag" => "allowed values: _data/stance_filters.yml → tags",
    "blank district" => "omit `district` entirely for statewide races",
    "state does not match file" => "the `state` field must equal the file's slug",
    "invalid primary_candidate" => "must be literally true or false",
    "inconsistent primary_candidate" => "it describes the candidate, so every row for them must agree",
    "invalid did_not_respond" => "must be literally true or false",
    "inconsistent did_not_respond" => "it describes the candidate, so every row for them must agree",
    "answer fields on non-responder" => "omit both `question` and `response` when did_not_respond is true",
    "inconsistent candidate details" => "these describe the candidate, so every row for them must agree",
    "duplicate response" => "one row per candidate per question",
    "duplicate candidate slug" => "each candidate's page URL is derived from their name; two candidates in one state cannot share one",
    "no state page for response file" => "responses are only reachable through their state page, and candidate pages link back to it",
    "missing county_race" => %(required whenever race is "#{COUNTY_RACE_RACE}"),
    "unexpected county_race" => %(only allowed when race is "#{COUNTY_RACE_RACE}"),
    "invalid races list" => "omit `races` when the question applies to every race",
    "referenced team image not found" => "when an image is listed, the file must exist under images/stance_teams/<state>/",
    "blank team image alt text" => "every team image needs descriptive `alt` text",
    "duplicate team image" => "list each team image only once",
    "unsafe team image path" => "use a filename only, without directories or path traversal",
  }.freeze

  # Beyond this a group is summarised; the pattern is already obvious by then.
  MAX_ENTRIES_PER_KIND = 20
  RULE_WIDTH = 72

  # The build's entry point. Each area collects problems without raising, so
  # every area runs before anything is reported: a contributor with a bad race
  # in stance_filters.yml *and* a duplicate response sees both at once instead
  # of discovering the second only after pushing a fix for the first. The areas
  # are independent — none of them consumes another's output — so running them
  # all on known-bad data cannot cascade. See AREAS at the foot of this module.
  def self.validate_all(site)
    sections = AREAS.filter_map do |method, title, footer|
      problems = send(method, site)
      [title, problems, footer] unless problems.empty?
    end

    report_and_raise_sections(sections)
  end

  # Run a single area on its own. The build uses validate_all; these remain so
  # one area can be exercised in isolation, as the tests do.
  def self.validate_one(method, site)
    _, title, footer = AREAS.find { |m, _, _| m == method }
    report_and_raise(title, send(method, site), footer)
  end

  def self.validate_filters(site) = validate_one(:filter_problems, site)
  def self.validate_state_pages(site) = validate_one(:state_page_problems, site)
  def self.validate(site) = validate_one(:response_problems, site)
  def self.validate_team_data(site) = validate_one(:team_problems, site)

  def self.filter_problems(site)
    filters = site.data[FILTERS_KEY]
    return [] unless filters

    races = Array(filters["races"])
    ballot_order = Array(filters["race_ballot_order"])
    file = "_data/stance_filters.yml"

    problems = []
    (races - ballot_order).each do |race|
      problems << Problem.new(:file => file, :kind => "missing from race_ballot_order", :detail => %("#{race}"))
    end
    (ballot_order - races).each do |race|
      problems << Problem.new(:file => file, :kind => "missing from races", :detail => %("#{race}"))
    end

    problems
  end

  def self.response_problems(site)
    filters = site.data[FILTERS_KEY]
    return [] unless filters

    valid_tags = Array(filters["tags"])
    valid_races = Array(filters["races"]).to_set
    valid_parties = Array(filters["parties"]).to_set
    race_overrides = filters["race_overrides"] || {}
    tag_set = valid_tags.to_set
    tag_lower = valid_tags.each_with_object({}) { |t, h| h[t.downcase] = t }

    problems = []

    question_ids_by_state = {}
    questions = site.data[QUESTIONS_KEY]
    if questions
      questions.each do |state_slug, entries|
        next if state_slug == "_blank"
        file = "_data/stance_questions/#{state_slug}.yml"
        state_valid_races = valid_races | Array(race_overrides[state_slug]).to_set
        seen_ids = {}
        Array(entries).each_with_index do |entry, idx|
          add = lambda do |kind, detail = nil|
            problems << Problem.new(:file => file, :row => idx, :kind => kind, :detail => detail,
                                    :subject => (entry["id"] if entry.is_a?(Hash)))
          end

          unless entry.is_a?(Hash)
            add.call("entry is not a mapping")
            next
          end

          QUESTION_REQUIRED_FIELDS.each do |f|
            if entry[f].nil? || (entry[f].is_a?(String) && entry[f].strip.empty?)
              add.call("missing required field", %("#{f}"))
            end
          end

          id = entry["id"]
          if id && !id.to_s.strip.empty?
            if seen_ids.key?(id)
              add.call("duplicate question id", %("#{id}" — also at entry #{seen_ids[id]}))
            else
              seen_ids[id] = idx
            end
          end

          validate_tags(entry["tag"], tag_set, tag_lower, add)

          # Race-specific questions are displayed on state pages, so validate
          # their applicability against the same canonical race list used by
          # candidate responses and explorer filters.
          question_races = entry["races"]
          unless question_races.nil?
            if !question_races.is_a?(Array)
              add.call("invalid races list", "must be a YAML list")
            elsif question_races.empty?
              add.call("invalid races list", "is empty")
            else
              question_races.each do |race|
                add.call("unknown race", %("#{race}")) unless state_valid_races.include?(race)
              end
            end
          end
        end
        question_ids_by_state[state_slug] = seen_ids.keys.to_set
      end
    end

    responses = site.data[RESPONSES_KEY]
    if responses
      responses.each do |state_slug, entries|
        next if state_slug == "_blank"
        file = "_data/stance_responses/#{state_slug}.yml"
        valid_question_ids = question_ids_by_state[state_slug] || Set.new
        flags_by_candidate = {}
        details_by_candidate = {}
        questions_by_candidate = {}
        names_by_slug = {}
        Array(entries).each_with_index do |entry, idx|
          name = candidate_name(entry)
          add = lambda do |kind, detail = nil|
            problems << Problem.new(:file => file, :row => idx, :kind => kind, :detail => detail,
                                    :subject => (name.empty? ? "(unnamed candidate)" : name))
          end

          unless entry.is_a?(Hash)
            add.call("entry is not a mapping")
            next
          end

          required = entry["did_not_respond"] == true ?
            RESPONSE_REQUIRED_FIELDS - NON_RESPONDER_EXEMPT_FIELDS : RESPONSE_REQUIRED_FIELDS
          required.each do |f|
            if entry[f].nil? || (entry[f].is_a?(String) && entry[f].strip.empty?)
              add.call("missing required field", %("#{f}"))
            end
          end

          if entry["state"] && entry["state"].to_s != state_slug.to_s
            add.call("state does not match file", %("#{entry["state"]}" — expected "#{state_slug}"))
          end

          if entry["race"] && !valid_races.include?(entry["race"])
            add.call("unknown race", %("#{entry["race"]}"))
          end

          if entry["party"] && !valid_parties.include?(entry["party"])
            add.call("unknown party", %("#{entry["party"]}"))
          end

          district = entry["district"]
          if !district.nil? && district.to_s.strip.empty?
            add.call("blank district")
          end

          date = entry["date"]
          unless date.nil?
            # YAML normally loads YYYY-MM-DD values as Date objects. Quoted
            # strings are also supported, but only in the same explicit format;
            # Date.parse would silently accept ambiguous values such as 7/8/26.
            iso_date_string = date.is_a?(String) && date.match?(/\A\d{4}-\d{2}-\d{2}\z/) &&
              (Date.iso8601(date) rescue nil)
            add.call("invalid date", %("#{date}")) unless date.is_a?(Date) || iso_date_string
          end

          question_ref = entry["question"]
          if question_ref && !question_ref.to_s.strip.empty? && !valid_question_ids.include?(question_ref)
            add.call("unknown question id", %("#{question_ref}" — no match in _data/stance_questions/#{state_slug}.yml))
          end

          # A candidate answers each question once. A repeat is a copy-paste slip
          # that would otherwise render as the same answer twice on their page.
          if !name.empty? && question_ref && !question_ref.to_s.strip.empty?
            seen_questions = (questions_by_candidate[name] ||= {})
            if seen_questions.key?(question_ref)
              add.call("duplicate response", %("#{question_ref}" — also at entry #{seen_questions[question_ref]}))
            else
              seen_questions[question_ref] = idx
            end
          end

          race_val = entry["race"]
          county_race_val = entry["county_race"]
          county_race_blank = county_race_val.nil? || (county_race_val.is_a?(String) && county_race_val.strip.empty?)
          if race_val == COUNTY_RACE_RACE && county_race_blank
            add.call("missing county_race")
          elsif !county_race_blank && race_val != COUNTY_RACE_RACE
            add.call("unexpected county_race", %("#{county_race_val}"))
          end

          CANDIDATE_FLAG_FIELDS.each do |f|
            flag = entry[f]
            next if flag.nil?
            add.call("invalid #{f}", %("#{flag}")) if flag != true && flag != false
          end

          # A candidate flagged as not having responded has no answer fields.
          # Rejecting both prevents a copied question id from creating a
          # misleading candidate/question association in downstream JSON.
          if entry["did_not_respond"] == true
            answer_fields_present = NON_RESPONDER_EXEMPT_FIELDS.any? do |field|
              value = entry[field]
              !value.nil? && !(value.is_a?(String) && value.strip.empty?)
            end
            add.call("answer fields on non-responder") if answer_fields_present
          end

          # These flags describe the candidate, not the individual response, so
          # each must be the same on every row for a given candidate. A missing
          # field and false mean the same thing.
          unless name.empty?
            flags = (flags_by_candidate[name] ||= {})
            CANDIDATE_FLAG_FIELDS.each do |f|
              (flags[f] ||= Set.new) << (entry[f] == true)
            end

            # Districts arrive from YAML as integers, so compare as strings, and
            # treat an absent value and a blank one as the same thing.
            fields = (details_by_candidate[name] ||= {})
            CANDIDATE_CONSISTENT_FIELDS.each do |f|
              value = entry[f]
              value = nil if value.is_a?(String) && value.strip.empty?
              (fields[f] ||= Set.new) << value&.to_s
            end

            (names_by_slug[StanceCandidate.slug(name)] ||= Set.new) << name
          end
        end

        flags_by_candidate.each do |cand_name, flags|
          flags.each do |field, values|
            next unless values.size > 1
            problems << Problem.new(:file => file, :subject => cand_name, :kind => "inconsistent #{field}")
          end
        end

        details_by_candidate.each do |cand_name, fields|
          fields.each do |field, values|
            next unless values.size > 1
            shown = values.map { |v| v.nil? ? "(none)" : %("#{v}") }.sort.join(" vs ")
            problems << Problem.new(:file => file, :subject => cand_name,
                                    :kind => "inconsistent candidate details", :detail => "#{field}: #{shown}")
          end
        end

        # Jekyll only logs a soft "Conflict:" warning when two pages want the same
        # destination, so a collision here would silently drop one candidate's page.
        names_by_slug.each do |slug, names|
          next unless names.size > 1
          problems << Problem.new(:file => file, :subject => names.sort.join(" / "),
                                  :kind => "duplicate candidate slug", :detail => %("#{slug}"))
        end
      end
    end

    problems
  end

  # Team cards are optional, but a referenced local image must be usable. Jekyll
  # copies missing references into the rendered HTML without failing the build,
  # so validate them explicitly here. Instagram-only entries remain valid, and
  # this intentionally does not require an entry to choose exactly one card type.
  def self.team_problems(site)
    teams = site.data[TEAM_KEY]
    return [] unless teams

    problems = []
    teams.each do |state_slug, entries|
      file = "_data/stance_team/#{state_slug}.yml"
      seen_images = {}

      Array(entries).each_with_index do |entry, idx|
        add = lambda do |kind, detail = nil|
          problems << Problem.new(:file => file, :row => idx, :kind => kind, :detail => detail,
                                  :subject => state_slug.to_s.upcase)
        end

        unless entry.is_a?(Hash)
          add.call("entry is not a mapping")
          next
        end

        image = entry["image"]
        next if image.nil?

        if !image.is_a?(String) || image.strip.empty? || File.basename(image) != image ||
           image == "." || image == ".." || image.include?("\\")
          add.call("unsafe team image path", %("#{image}"))
          next
        end

        alt = entry["alt"]
        add.call("blank team image alt text", %("#{image}")) if !alt.is_a?(String) || alt.strip.empty?

        if seen_images.key?(image)
          add.call("duplicate team image", %("#{image}" — also at entry #{seen_images[image]}))
        else
          seen_images[image] = idx
        end

        image_path = File.join(site.source, "images", "stance_teams", state_slug.to_s, image)
        add.call("referenced team image not found", %("#{image}")) unless File.file?(image_path)
      end
    end

    problems
  end

  def self.candidate_name(entry)
    return "" unless entry.is_a?(Hash)
    [entry["candidate_first_name"], entry["candidate_last_name"]].compact.join(" ").strip
  end

  # Every state page must declare the front matter its body and the shared
  # includes depend on. These are the single source of truth for the state's
  # code, display name, contact link, and voter-lookup link across the map,
  # filter bar, response cards, responses.json feed, and page header — a missing
  # value silently leaks blanks or broken links, so fail the build instead. This
  # list mirrors the "Required front matter" section documented in template.html.
  #
  # State pages are identified by their location (files under the states
  # directory) rather than by the presence of a `state` field, so that a page
  # which forgot `state` entirely is still caught instead of silently ignored.
  TEMPLATE_STATE_CODE = "xx".freeze
  STATE_PAGE_DIR = "stance/states/".freeze
  TEMPLATE_BASENAME = "template.html".freeze
  STATE_PAGE_REQUIRED_FIELDS = %w[
    state state_name demonym_plural team_email ballot_lookup_url ballot_lookup_label
  ].freeze

  def self.state_page_problems(site)
    collection = site.collections["initiatives"]
    return [] unless collection

    problems = []
    page_states = Set.new
    collection.docs.each do |doc|
      path = doc.relative_path.to_s
      next unless path.include?(STATE_PAGE_DIR)
      next if File.basename(path) == TEMPLATE_BASENAME
      # The template placeholder renders at the `xx` code; skip any copy still
      # carrying it (it isn't a real, published state page).
      next if doc.data["state"].to_s == TEMPLATE_STATE_CODE

      page_states << doc.data["state"].to_s

      STATE_PAGE_REQUIRED_FIELDS.each do |f|
        value = doc.data[f]
        if value.nil? || (value.is_a?(String) && value.strip.empty?)
          problems << Problem.new(:file => path, :kind => "missing required front matter", :detail => %("#{f}"))
        end
      end
    end

    # The reverse direction: a response file with no state page would strand its
    # candidates. Their names still link to generated candidate pages, and those
    # pages link back to a state page that does not exist. (A state page with no
    # response file is fine — it just has nothing to show yet.)
    (site.data[RESPONSES_KEY] || {}).each_key do |state_slug|
      next if state_slug == "_blank"
      next if page_states.include?(state_slug.to_s)

      problems << Problem.new(:file => "_data/stance_responses/#{state_slug}.yml",
                              :kind => "no state page for response file",
                              :detail => %(no page under _initiatives/#{STATE_PAGE_DIR} declares state: "#{state_slug}"))
    end

    problems
  end

  def self.validate_tags(tags, tag_set, tag_lower, add)
    return if tags.nil?
    tag_list = tags.is_a?(Array) ? tags : [tags]
    tag_list.each do |tag|
      next if tag_set.include?(tag)
      hint = tag_lower[tag.to_s.downcase]
      suffix = hint ? %( — did you mean "#{hint}"?) : ""
      add.call("unknown tag", %("#{tag}"#{suffix}))
    end
  end

  def self.report_and_raise(title, problems, footer)
    report_and_raise_sections(problems.empty? ? [] : [[title, problems, footer]])
  end

  # Jekyll's logger squashes every run of whitespace in an exception message
  # into a single space (see Jekyll::LogAdapter#message), which turns a
  # multi-line report into one unreadable paragraph. So print the real report to
  # stderr ourselves and raise only a one-line summary that points at it.
  def self.report_and_raise_sections(sections)
    return if sections.empty?

    report = sections.map { |title, problems, footer| render(title, problems, footer) }.join("\n")
    $stderr.puts(report)
    $stderr.flush
    write_report_file(report)

    problems = sections.flat_map { |_, area_problems, _| area_problems }
    files = problems.map(&:file).uniq.size
    # One area failing keeps its own heading; several share a generic one,
    # because each section already carries its heading in the report above.
    title = sections.size == 1 ? sections.first.first : "Stance validation failed"
    raise "#{title}: #{plural(problems.size, "problem")} in #{plural(files, "file")} " \
          "(full report printed above)."
  end

  # CI opens an issue when the deploy fails. Writing the report to the path in
  # STANCE_VALIDATION_REPORT lets that workflow quote it verbatim instead of
  # scraping it back out of the job log, where it is buried between Jekyll's
  # progress output and its backtrace.
  def self.write_report_file(report)
    path = ENV["STANCE_VALIDATION_REPORT"].to_s
    return if path.empty?

    File.write(path, "#{report.gsub(%r!\e\[[0-9;]*m!, "")}\n")
  rescue SystemCallError => e
    warn "Could not write validation report to #{path}: #{e.message}"
  end

  def self.render(title, problems, footer)
    rule = "=" * RULE_WIDTH
    files = problems.group_by(&:file)

    out = ["", red(rule), red(bold(title)),
           red("#{plural(problems.size, "problem")} in #{plural(files.size, "file")}"), red(rule)]

    files.each do |file, file_problems|
      out << ""
      out << "#{bold(file)}  (#{file_problems.size})"

      file_problems.group_by(&:kind).each do |kind, kind_problems|
        out << ""
        out << "  #{yellow(kind)} (#{kind_problems.size})"
        out << dim("    #{HINTS[kind]}") if HINTS[kind]

        lines = summarize(kind_problems)
        lines.first(MAX_ENTRIES_PER_KIND).each { |line| out << "    #{line}" }
        if lines.size > MAX_ENTRIES_PER_KIND
          out << dim("    ...and #{lines.size - MAX_ENTRIES_PER_KIND} more like this")
        end
      end
    end

    out << ""
    out << footer
    out << dim("Entry numbers are 0-based positions in the YAML list.") if problems.any?(&:row)
    out << ""
    out.join("\n")
  end

  # Collapse problems that say the same thing about the same subject into one
  # line with a compacted range of entry numbers, so 40 identical typos read as
  # "entries 40-79" instead of forty near-identical lines.
  def self.summarize(problems)
    entries = problems.group_by { |p| [p.subject, p.detail] }.map do |(subject, detail), group|
      rows = group.map(&:row).compact.uniq.sort
      [rows.first || -1, row_label(rows), [subject, detail].compact.reject { |s| s.to_s.empty? }.join(": ")]
    end
    entries.sort_by! { |first_row, _, description| [first_row, description] }

    width = entries.map { |_, label, _| label.length }.max.to_i
    entries.map do |_, label, description|
      width.zero? ? description : "#{label.ljust(width)}  #{description}"
    end
  end

  def self.row_label(rows)
    return "" if rows.empty?

    ranges = rows.slice_when { |a, b| b != a + 1 }.map do |run|
      run.size == 1 ? run.first.to_s : "#{run.first}-#{run.last}"
    end
    "#{rows.size == 1 ? "entry" : "entries"} #{ranges.join(", ")}"
  end

  def self.plural(count, noun)
    "#{count} #{noun}#{"s" unless count == 1}"
  end

  def self.color?
    return @color unless @color.nil?
    @color = $stderr.tty? && ENV["NO_COLOR"].to_s.empty?
  end

  def self.paint(code, text)
    color? ? "\e[#{code}m#{text}\e[0m" : text
  end

  def self.bold(text) = paint("1", text)
  def self.dim(text) = paint("2", text)
  def self.red(text) = paint("31", text)
  def self.yellow(text) = paint("33", text)

  # The four independent areas, in report order: the method that collects that
  # area's problems, the heading its section carries, and the footer pointing at
  # where its valid values are defined. Declared last because the footers read
  # constants defined above; Ruby resolves AREAS when validate_all is called,
  # long after this file has finished loading.
  AREAS = [
    [:filter_problems, "Stance filter validation failed",
     "`races` and `race_ballot_order` must contain exactly the same entries."],
    [:state_page_problems, "Stance state page validation failed",
     "Every state page must define: #{STATE_PAGE_REQUIRED_FIELDS.join(", ")}."],
    [:response_problems, "Stance response validation failed",
     "Valid values are defined in _data/stance_filters.yml."],
    [:team_problems, "Stance team validation failed",
     "Team image files and alt text are defined in _data/stance_team/<state>.yml."],
  ].freeze
end

Jekyll::Hooks.register :site, :post_read do |site|
  StanceResponseValidator.validate_all(site)
end
