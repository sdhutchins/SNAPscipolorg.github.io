#!/usr/bin/env ruby
# frozen_string_literal: true

# Run the Stance on Science data validators without building the site.
#
#   bundle exec ruby bin/validate_stance.rb
#
# The validators themselves live in _plugins/stance_tag_validator.rb and run on
# Jekyll's :site, :post_read hook during every build. That build is still the
# authority: it also catches failures this script cannot see, such as Liquid
# errors raised while rendering response Markdown through the `liquify` filter.
# What this script buys is speed — it loads only the four data sets and the
# front matter the validators read, which is a fraction of a second against the
# full corpus, so a contributor can check a YAML edit before pushing it.
#
# The cost of that speed is this file: a second, smaller reader alongside
# Jekyll's. Keep it faithful to how Jekyll loads _data and collection front
# matter. If the two ever disagree, the build wins — a green run here is a
# strong signal, not a guarantee.
#
# Exits 0 when the data is clean, 1 otherwise. Honours STANCE_VALIDATION_REPORT
# exactly as the build does: set it to a path and the full grouped report is
# written there as well as printed.

require "date"
require "set"
require "yaml"

# Candidate page URLs come from Jekyll::Utils.slugify, and the validator checks
# for slug collisions, so the real implementation has to be loaded rather than
# approximated. This also loads Liquid, which the shared filters file registers
# into on require.
require "jekyll"

require_relative "../_plugins/stance_tag_validator"

module StanceStandaloneCheck
  SOURCE = File.expand_path("..", __dir__)

  # site.data keys the validators read, and where Jekyll gets each one from. A
  # single file becomes its parsed contents; a directory becomes a hash keyed by
  # each file's basename ("_data/stance_responses/ca.yml" -> "ca").
  DATA_FILES = { "stance_filters" => "_data/stance_filters.yml" }.freeze
  DATA_DIRS = {
    "stance_questions" => "_data/stance_questions",
    "stance_responses" => "_data/stance_responses",
    "stance_team" => "_data/stance_team",
  }.freeze

  # The state pages the validator checks front matter on live in this
  # collection. Jekyll gives a document a relative_path that keeps the
  # collection directory ("_initiatives/stance/states/nj.html"), and the
  # validator prints that path on a problem, so build the same string here.
  COLLECTION = "initiatives"
  COLLECTION_DIR = "_initiatives"
  COLLECTION_EXTENSIONS = %w[html md markdown].freeze

  # YAML dates (a response's `date`) load as Date objects under Jekyll too; the
  # validator distinguishes those from strings, so they must be permitted here.
  PERMITTED_YAML_CLASSES = [Date, Time].freeze

  FRONT_MATTER = %r{\A---\s*\n(.*?)\n---\s*\n}m

  Doc = Struct.new(:relative_path, :data)
  Collection = Struct.new(:docs)
  Site = Struct.new(:data, :source, :collections)

  def self.site
    data = DATA_FILES.to_h { |key, path| [key, load_yaml(absolute(path))] }
    DATA_DIRS.each { |key, dir| data[key] = load_dir(dir) }

    Site.new(data, SOURCE, { COLLECTION => Collection.new(collection_docs) })
  end

  def self.load_dir(dir)
    Dir.glob(File.join(absolute(dir), "*.yml")).sort.to_h do |path|
      [File.basename(path, ".yml"), load_yaml(path)]
    end
  end

  def self.collection_docs
    pattern = File.join(absolute(COLLECTION_DIR), "**", "*.{#{COLLECTION_EXTENSIONS.join(",")}}")
    Dir.glob(pattern).sort.map { |path| Doc.new(relative(path), front_matter(path)) }
  end

  def self.load_yaml(path)
    abort "Missing #{relative(path)}" unless File.file?(path)

    YAML.safe_load(File.read(path), :permitted_classes => PERMITTED_YAML_CLASSES, :aliases => true)
  rescue Psych::SyntaxError => e
    # A malformed data file fails the build with a bare parser backtrace, so
    # name the file and the line instead.
    abort "#{relative(path)}: YAML syntax error at line #{e.line}, column #{e.column}: #{e.problem}"
  end

  # A page with no front matter is a static file to Jekyll, not a document, so
  # it never reaches the validator. Represent that as empty data rather than
  # skipping it, so a state page that lost its front matter is still reported
  # as missing every required field.
  def self.front_matter(path)
    match = File.read(path).match(FRONT_MATTER)
    return {} unless match

    YAML.safe_load(match[1], :permitted_classes => PERMITTED_YAML_CLASSES, :aliases => true) || {}
  rescue Psych::SyntaxError => e
    abort "#{relative(path)}: front matter syntax error at line #{e.line}: #{e.problem}"
  end

  def self.absolute(path) = File.join(SOURCE, path)
  def self.relative(path) = path.sub("#{SOURCE}/", "")

  def self.summary(site)
    responses = site.data["stance_responses"].reject { |slug, _| slug == "_blank" }
    questions = site.data["stance_questions"].reject { |slug, _| slug == "_blank" }
    rows = responses.values.sum { |entries| Array(entries).size }

    "#{rows} responses across #{responses.size} states, " \
      "#{questions.values.sum { |entries| Array(entries).size }} questions, " \
      "#{site.data["stance_team"].values.sum { |entries| Array(entries).size }} team entries"
  end
end

site = StanceStandaloneCheck.site

begin
  StanceResponseValidator.validate_all(site)
rescue RuntimeError => e
  # validate_all has already printed the full grouped report to stderr; this is
  # the one-line summary that points at it.
  warn e.message
  exit 1
end

puts "Stance data OK — #{StanceStandaloneCheck.summary(site)}."
