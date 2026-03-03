---
title: "the book is a program"
url: "https://docs.racket-lang.org/pollen/index.html"
date_fetched: "2026-02-16"
type: webpage
---

Title: the book is a program

URL Source: https://docs.racket-lang.org/pollen/index.html

Published Time: Mon, 16 Feb 2026 00:09:40 GMT

Markdown Content:
Pollen: the book is a program
===============

[▼](javascript:void(0); "Expand/Collapse")[Pollen: the book is a program](https://docs.racket-lang.org/pollen/index.html)

1[Installation](https://docs.racket-lang.org/pollen/Installation.html)
2[Quick tour](https://docs.racket-lang.org/pollen/quick-tour.html)
3[Backstory](https://docs.racket-lang.org/pollen/Backstory.html)
4[The big picture](https://docs.racket-lang.org/pollen/big-picture.html)
5[First tutorial: the project server & preprocessor](https://docs.racket-lang.org/pollen/first-tutorial.html)
6[Second tutorial: Markdown, templates, & pagetrees](https://docs.racket-lang.org/pollen/second-tutorial.html)
7[Third tutorial: Pollen markup & tag functions](https://docs.racket-lang.org/pollen/third-tutorial.html)
8[Fourth tutorial: multiple output targets](https://docs.racket-lang.org/pollen/fourth-tutorial.html)
9[Mini tutorials](https://docs.racket-lang.org/pollen/mini-tutorial.html)
10[Using raco pollen](https://docs.racket-lang.org/pollen/raco-pollen.html)
11[File formats](https://docs.racket-lang.org/pollen/File_formats.html)
12[Pollen command syntax](https://docs.racket-lang.org/pollen/pollen-command-syntax.html)
13[Programming Pollen](https://docs.racket-lang.org/pollen/programming-pollen.html)
14[Module reference](https://docs.racket-lang.org/pollen/Module_reference.html)
15[Unstable module reference](https://docs.racket-lang.org/pollen/Unstable_module_reference.html)
16[Acknowledgments](https://docs.racket-lang.org/pollen/Acknowledgments.html)
17[License & source code](https://docs.racket-lang.org/pollen/License___source_code.html)
18[Version notes (3.2.4581.976)](https://docs.racket-lang.org/pollen/version-notes.html)
[Index](https://docs.racket-lang.org/pollen/doc-index.html)

On this page:

[Pollen: the book is a program](https://docs.racket-lang.org/pollen/index.html#%28part._top%29)

[![Image 2: Racket](https://racket-lang.org/logo-and-text-1-2.png)](https://racket-lang.org/)

9.0

[top](https://docs.racket-lang.org/index.html "up to the documentation top")[contents](javascript:void(0); "show/hide table of contents")← prev[up](https://docs.racket-lang.org/index.html "up to the documentation top")[next →](https://docs.racket-lang.org/pollen/Installation.html "forward to \"1 Installation\"")

[](https://docs.racket-lang.org/pollen/index.html)[](https://docs.racket-lang.org/pollen/index.html)[](https://docs.racket-lang.org/pollen/index.html)Pollen: the book is a program[🔗](https://docs.racket-lang.org/pollen/index.html#(part._top) "Link to here")[ℹ](https://docs.racket-lang.org/pollen/index.html "Internal Scribble link and Scribble source")
==================================================================================================================================================================================================================================================================================================================================================================

Link to this document with 

@other-doc['(lib "pollen/scribblings/pollen.scrbl")]

Document source 

[https://gitlab.com/mbutterick/pollen/-/blob/master/pollen/scribblings/pollen.scrbl](https://gitlab.com/mbutterick/pollen/-/blob/master/pollen/scribblings/pollen.scrbl)

Link to this document with 

@other-doc['(lib "pollen/scribblings/pollen.scrbl")]

Document source 

[https://gitlab.com/mbutterick/pollen/-/blob/master/pollen/scribblings/pollen.scrbl](https://gitlab.com/mbutterick/pollen/-/blob/master/pollen/scribblings/pollen.scrbl)

Matthew Butterick <[mb@mbtype.com](mailto:mb@mbtype.com)>

[#lang](https://docs.racket-lang.org/guide/Module_Syntax.html#%28part._hash-lang%29)[pollen](https://docs.racket-lang.org/pollen/index.html)package:[pollen](https://pkgs.racket-lang.org/package/pollen "Install this package using `raco pkg install pollen`")

Pollen is a publishing system that helps authors make functional and beautiful digital books.

I created Pollen so I could make my web-based books [Practical Typography](http://practicaltypography.com/), [Typography for Lawyers](http://typographyforlawyers.com/), and [Beautiful Racket](http://beautifulracket.com/). Sure, go take a look. Are they better than the last digital books you encountered? Yes they are. Would you like your next digital book to work like that? If so, keep reading.

At the core of Pollen is an argument:

1.   Digital books should be the best books we’ve ever had. So far, they’re not even close.

2.   Because digital books are software, an author shouldn’t think of a book as merely data. The book is a program.

3.   The way we make digital books better than their predecessors is by exploiting this programmability.

That’s what Pollen is for.

Not that you need to be a programmer to start using Pollen. On the contrary, the Pollen language is markup-based, so you can write & edit text naturally. But when you want to automate repetitive tasks, add cross-references, or pull in data from other sources, you can access a full programming language from within the text.

That language is [Racket](http://racket-lang.org/). I chose Racket because it has some unique features that made Pollen possible. So if it’s unfamiliar to you, don’t panic. It was unfamiliar to me. Once you see what you can do with Racket & Pollen, you may be persuaded. I was.

Or, if you can find a better digital-publishing tool, use that. But I’m never going back to the way I used to work.

[1 Installation](https://docs.racket-lang.org/pollen/Installation.html)
[1.1 Prerequisites](https://docs.racket-lang.org/pollen/Installation.html#%28part._.Prerequisites%29)
[1.2 How to install](https://docs.racket-lang.org/pollen/Installation.html#%28part._.How_to_install%29)
[1.3 Beyond that](https://docs.racket-lang.org/pollen/Installation.html#%28part._.Beyond_that%29)
[1.4 Getting more help](https://docs.racket-lang.org/pollen/Installation.html#%28part._.Getting_more_help%29)
[1.4.1 Bugs and feature requests](https://docs.racket-lang.org/pollen/Installation.html#%28part._.Bugs_and_feature_requests%29)
[1.4.2 Can I see the source for Practical Typography or Typography for Lawyers?](https://docs.racket-lang.org/pollen/Installation.html#%28part._.Can_.I_see_the_source_for_.Practical_.Typography_or_.Typography_for_.Lawyers_%29)
[1.4.3 Utilities & libraries](https://docs.racket-lang.org/pollen/Installation.html#%28part._.Utilities___libraries%29)
[1.4.4 More projects & guides](https://docs.racket-lang.org/pollen/Installation.html#%28part._.More_projects___guides%29)

[2 Quick tour](https://docs.racket-lang.org/pollen/quick-tour.html)
[2.1 Creating a source file](https://docs.racket-lang.org/pollen/quick-tour.html#%28part._.Creating_a_source_file%29)
[2.2 Running a source file](https://docs.racket-lang.org/pollen/quick-tour.html#%28part._.Running_a_source_file%29)
[2.3 Naming, saving, and rendering a source file](https://docs.racket-lang.org/pollen/quick-tour.html#%28part._.Naming__saving__and_rendering_a_source_file%29)
[2.4 The project server](https://docs.racket-lang.org/pollen/quick-tour.html#%28part._.The_project_server%29)
[2.5 Intermission](https://docs.racket-lang.org/pollen/quick-tour.html#%28part._.Intermission%29)
[2.6 Pollen as a preprocessor](https://docs.racket-lang.org/pollen/quick-tour.html#%28part._.Pollen_as_a_preprocessor%29)
[2.7 Markdown mode](https://docs.racket-lang.org/pollen/quick-tour.html#%28part._.Markdown_mode%29)
[2.8 Pollen markup](https://docs.racket-lang.org/pollen/quick-tour.html#%28part._.Pollen_markup%29)
[2.9 Templates](https://docs.racket-lang.org/pollen/quick-tour.html#%28part._.Templates%29)
[2.10 PS for Scribble users](https://docs.racket-lang.org/pollen/quick-tour.html#%28part._.P.S_for_.Scribble_users%29)
[2.11 The end of the beginning](https://docs.racket-lang.org/pollen/quick-tour.html#%28part._.The_end_of_the_beginning%29)

[3 Backstory](https://docs.racket-lang.org/pollen/Backstory.html)
[3.1 Web development and its discontents](https://docs.racket-lang.org/pollen/Backstory.html#%28part._.Web_development_and_its_discontents%29)
[3.2 The better idea: a programming model](https://docs.racket-lang.org/pollen/Backstory.html#%28part._.The_better_idea__a_programming_model%29)
[3.3“Now you have two problems”](https://docs.racket-lang.org/pollen/Backstory.html#%28part.__.Now_you_have_two_problems_%29)
[3.4 Rethinking the solution for digital books](https://docs.racket-lang.org/pollen/Backstory.html#%28part._.Rethinking_the_solution_for_digital_books%29)
[3.5 Enter Racket](https://docs.racket-lang.org/pollen/Backstory.html#%28part._.Enter_.Racket%29)
[3.6 What is Pollen?](https://docs.racket-lang.org/pollen/Backstory.html#%28part._.What_is_.Pollen_%29)

[4 The big picture](https://docs.racket-lang.org/pollen/big-picture.html)
[4.1 The book is a program](https://docs.racket-lang.org/pollen/big-picture.html#%28part._the-book-is-a-program%29)
[4.2 One language, multiple dialects](https://docs.racket-lang.org/pollen/big-picture.html#%28part._.One_language__multiple_dialects%29)
[4.3 Development environment](https://docs.racket-lang.org/pollen/big-picture.html#%28part._.Development_environment%29)
[4.4 A special data structure for HTML](https://docs.racket-lang.org/pollen/big-picture.html#%28part._.A_special_data_structure_for_.H.T.M.L%29)
[4.5 Pollen command syntax](https://docs.racket-lang.org/pollen/big-picture.html#%28part._.Pollen_command_syntax%29)
[4.6 The preprocessor](https://docs.racket-lang.org/pollen/big-picture.html#%28part._.The_preprocessor%29)
[4.7 Templated source files](https://docs.racket-lang.org/pollen/big-picture.html#%28part._.Templated_source_files%29)
[4.8 Pagetrees](https://docs.racket-lang.org/pollen/big-picture.html#%28part._.Pagetrees%29)

[5 First tutorial: the project server & preprocessor](https://docs.racket-lang.org/pollen/first-tutorial.html)
[5.1 Prerequisites](https://docs.racket-lang.org/pollen/first-tutorial.html#%28part._tutorial-1._.Prerequisites%29)
[5.2 Optional reading: the relationship of Racket & Pollen](https://docs.racket-lang.org/pollen/first-tutorial.html#%28part._.Optional_reading__the_relationship_of_.Racket___.Pollen%29)
[5.3 Starting a new file in DrRacket](https://docs.racket-lang.org/pollen/first-tutorial.html#%28part._.Starting_a_new_file_in_.Dr.Racket%29)
[5.3.1 Setting the #lang line](https://docs.racket-lang.org/pollen/first-tutorial.html#%28part._.Setting_the__lang_line%29)
[5.3.2 Putting in the text of the poem](https://docs.racket-lang.org/pollen/first-tutorial.html#%28part._.Putting_in_the_text_of_the_poem%29)
[5.3.3 Saving & naming your source file](https://docs.racket-lang.org/pollen/first-tutorial.html#%28part._.Saving___naming_your_source_file%29)
[5.4 Using the project server](https://docs.racket-lang.org/pollen/first-tutorial.html#%28part._.Using_the_project_server%29)
[5.4.1 Starting the project server with raco pollen](https://docs.racket-lang.org/pollen/first-tutorial.html#%28part._.Starting_the_project_server_with_raco_pollen%29)
[5.4.2 The project dashboard](https://docs.racket-lang.org/pollen/first-tutorial.html#%28part._.The_project_dashboard%29)
[5.4.3 Source files in the dashboard](https://docs.racket-lang.org/pollen/first-tutorial.html#%28part._.Source_files_in_the_dashboard%29)
[5.5 Working with the preprocessor](https://docs.racket-lang.org/pollen/first-tutorial.html#%28part._.Working_with_the_preprocessor%29)
[5.5.1 Setting up a preprocessor source file](https://docs.racket-lang.org/pollen/first-tutorial.html#%28part._.Setting_up_a_preprocessor_source_file%29)
[5.5.2 Creating valid HTML output](https://docs.racket-lang.org/pollen/first-tutorial.html#%28part._.Creating_valid_.H.T.M.L_output%29)
[5.5.3 Adding Pollen commands](https://docs.racket-lang.org/pollen/first-tutorial.html#%28part._.Adding_.Pollen_commands%29)
[5.5.4 Racket basics (if you’re not familiar)](https://docs.racket-lang.org/pollen/first-tutorial.html#%28part._.Racket_basics__if_you_re_not_familiar_%29)
[5.5.5 Defining variables with Racket-style commands](https://docs.racket-lang.org/pollen/first-tutorial.html#%28part._.Defining_variables_with_.Racket-style_commands%29)
[5.5.6 Inserting values from variables](https://docs.racket-lang.org/pollen/first-tutorial.html#%28part._.Inserting_values_from_variables%29)
[5.5.7 Inserting variables within CSS](https://docs.racket-lang.org/pollen/first-tutorial.html#%28part._.Inserting_variables_within_.C.S.S%29)
[5.6 First tutorial complete](https://docs.racket-lang.org/pollen/first-tutorial.html#%28part._.First_tutorial_complete%29)

[6 Second tutorial: Markdown, templates, & pagetrees](https://docs.racket-lang.org/pollen/second-tutorial.html)
[6.1 Prerequisites](https://docs.racket-lang.org/pollen/second-tutorial.html#%28part._tutorial-2._.Prerequisites%29)
[6.2 Optional reading: the case against Markdown](https://docs.racket-lang.org/pollen/second-tutorial.html#%28part._the-case-against-markdown%29)
[6.3 Markdown in Pollen: two options](https://docs.racket-lang.org/pollen/second-tutorial.html#%28part._.Markdown_in_.Pollen__two_options%29)
[6.3.1 Using Markdown with the preprocessor](https://docs.racket-lang.org/pollen/second-tutorial.html#%28part._.Using_.Markdown_with_the_preprocessor%29)
[6.3.2 Authoring mode](https://docs.racket-lang.org/pollen/second-tutorial.html#%28part._.Authoring_mode%29)
[6.3.3 X-expressions](https://docs.racket-lang.org/pollen/second-tutorial.html#%28part._.X-expressions%29)
[6.3.4 Markdown authoring mode](https://docs.racket-lang.org/pollen/second-tutorial.html#%28part._.Markdown_authoring_mode%29)
[6.3.5 Review: authoring mode vs. preprocessor mode](https://docs.racket-lang.org/pollen/second-tutorial.html#%28part._.Review__authoring_mode_vs__preprocessor_mode%29)
[6.4 Templates](https://docs.racket-lang.org/pollen/second-tutorial.html#%28part._tutorial-2._.Templates%29)
[6.4.1 The doc export and the ->html function](https://docs.racket-lang.org/pollen/second-tutorial.html#%28part._tutorial-2._.The_doc_export_and_the_-_html_function%29)
[6.4.2 Making a custom template](https://docs.racket-lang.org/pollen/second-tutorial.html#%28part._tutorial-2._.Making_a_custom_template%29)
[6.4.3 Inserting specific source data into templates](https://docs.racket-lang.org/pollen/second-tutorial.html#%28part._tutorial-2._.Inserting_specific_source_data_into_templates%29)
[6.4.4 Linking to an external CSS file](https://docs.racket-lang.org/pollen/second-tutorial.html#%28part._tutorial-2._.Linking_to_an_external_.C.S.S_file%29)
[6.5 Intermission](https://docs.racket-lang.org/pollen/second-tutorial.html#%28part._tutorial-2._.Intermission%29)
[6.6 Pagetrees](https://docs.racket-lang.org/pollen/second-tutorial.html#%28part._tutorial-2._.Pagetrees%29)
[6.6.1 Pagetree navigation](https://docs.racket-lang.org/pollen/second-tutorial.html#%28part._tutorial-2._.Pagetree_navigation%29)
[6.6.2 Using the automatic pagetree](https://docs.racket-lang.org/pollen/second-tutorial.html#%28part._tutorial-2._.Using_the_automatic_pagetree%29)
[6.6.3 Adding navigation links to the template with here](https://docs.racket-lang.org/pollen/second-tutorial.html#%28part._tutorial-2._.Adding_navigation_links_to_the_template_with_here%29)
[6.6.4 Handling navigation boundaries with conditionals](https://docs.racket-lang.org/pollen/second-tutorial.html#%28part._tutorial-2._.Handling_navigation_boundaries_with_conditionals%29)
[6.6.5 Making a pagetree file](https://docs.racket-lang.org/pollen/second-tutorial.html#%28part._tutorial-2._.Making_a_pagetree_file%29)
[6.6.6 index.ptree& the project server](https://docs.racket-lang.org/pollen/second-tutorial.html#%28part._tutorial-2._index_ptree___the_project_server%29)
[6.7 Second tutorial complete](https://docs.racket-lang.org/pollen/second-tutorial.html#%28part._.Second_tutorial_complete%29)

[7 Third tutorial: Pollen markup & tag functions](https://docs.racket-lang.org/pollen/third-tutorial.html)
[7.1 Prerequisites](https://docs.racket-lang.org/pollen/third-tutorial.html#%28part._tutorial-3._.Prerequisites%29)
[7.2 Optional reading: Pollen markup vs. XML](https://docs.racket-lang.org/pollen/third-tutorial.html#%28part._pollen-vs-xml%29)
[7.2.1 The XML problem](https://docs.racket-lang.org/pollen/third-tutorial.html#%28part._.The_.X.M.L_problem%29)
[7.2.2 What Pollen markup does differently](https://docs.racket-lang.org/pollen/third-tutorial.html#%28part._.What_.Pollen_markup_does_differently%29)
[7.2.3“But I really need XML…”](https://docs.racket-lang.org/pollen/third-tutorial.html#%28part.__.But_.I_really_need_.X.M.L~e2~80~a6_%29)
[7.3 Writing with Pollen markup](https://docs.racket-lang.org/pollen/third-tutorial.html#%28part._.Writing_with_.Pollen_markup%29)
[7.3.1 Creating a Pollen markup file](https://docs.racket-lang.org/pollen/third-tutorial.html#%28part._.Creating_a_.Pollen_markup_file%29)
[7.3.2 Tags & tag functions](https://docs.racket-lang.org/pollen/third-tutorial.html#%28part._.Tags___tag_functions%29)
[7.3.3 Attributes](https://docs.racket-lang.org/pollen/third-tutorial.html#%28part._.Attributes%29)
[7.3.4 Optional reading: What are custom tags good for?](https://docs.racket-lang.org/pollen/third-tutorial.html#%28part._.Optional_reading__.What_are_custom_tags_good_for_%29)
[7.3.4.1 Semantic markup](https://docs.racket-lang.org/pollen/third-tutorial.html#%28part._.Semantic_markup%29)
[7.3.4.2 Format independence](https://docs.racket-lang.org/pollen/third-tutorial.html#%28part._.Format_independence%29)
[7.3.5 Using custom tags](https://docs.racket-lang.org/pollen/third-tutorial.html#%28part._.Using_custom_tags%29)
[7.3.6 Choosing custom tags](https://docs.racket-lang.org/pollen/third-tutorial.html#%28part._.Choosing_custom_tags%29)
[7.4 Tags are functions](https://docs.racket-lang.org/pollen/third-tutorial.html#%28part._tags-are-functions%29)
[7.4.1 Attaching behavior to tags](https://docs.racket-lang.org/pollen/third-tutorial.html#%28part._.Attaching_behavior_to_tags%29)
[7.5 Intermission](https://docs.racket-lang.org/pollen/third-tutorial.html#%28part._tutorial-3._.Intermission%29)
[7.6 Organizing functions](https://docs.racket-lang.org/pollen/third-tutorial.html#%28part._.Organizing_functions%29)
[7.6.1 Using Racket’s function libraries](https://docs.racket-lang.org/pollen/third-tutorial.html#%28part._.Using_.Racket_s_function_libraries%29)
[7.6.2 Introducing "pollen.rkt"](https://docs.racket-lang.org/pollen/third-tutorial.html#%28part._tutorial-3._.Introducing__pollen_rkt_%29)
[7.7 Decoding markup with a root tag function](https://docs.racket-lang.org/pollen/third-tutorial.html#%28part._.Decoding_markup_with_a_root_tag_function%29)
[7.8 Putting it all together](https://docs.racket-lang.org/pollen/third-tutorial.html#%28part._.Putting_it_all_together%29)
[7.8.1 The "pollen.rkt" file](https://docs.racket-lang.org/pollen/third-tutorial.html#%28part._tutorial-3._.The__pollen_rkt__file%29)
[7.8.2 The template](https://docs.racket-lang.org/pollen/third-tutorial.html#%28part._.The_template%29)
[7.8.3 The pagetree](https://docs.racket-lang.org/pollen/third-tutorial.html#%28part._.The_pagetree%29)
[7.8.4 A CSS stylesheet using the preprocessor](https://docs.racket-lang.org/pollen/third-tutorial.html#%28part._.A_.C.S.S_stylesheet_using_the_preprocessor%29)
[7.8.5 The content source files using Pollen markup](https://docs.racket-lang.org/pollen/third-tutorial.html#%28part._.The_content_source_files_using_.Pollen_markup%29)
[7.8.6 The result](https://docs.racket-lang.org/pollen/third-tutorial.html#%28part._.The_result%29)
[7.9 Third tutorial complete](https://docs.racket-lang.org/pollen/third-tutorial.html#%28part._.Third_tutorial_complete%29)

[8 Fourth tutorial: multiple output targets](https://docs.racket-lang.org/pollen/fourth-tutorial.html)
[8.1 Prerequisites](https://docs.racket-lang.org/pollen/fourth-tutorial.html#%28part._tutorial-4._.Prerequisites%29)
[8.2 Optional reading: Multiple-output publishing and its discontents](https://docs.racket-lang.org/pollen/fourth-tutorial.html#%28part._.Optional_reading__.Multiple-output_publishing_and_its_discontents%29)
[8.2.1 And let’s not leave out programmability](https://docs.racket-lang.org/pollen/fourth-tutorial.html#%28part._.And_let_s_not_leave_out_programmability%29)
[8.2.2 One source, multiple outputs](https://docs.racket-lang.org/pollen/fourth-tutorial.html#%28part._.One_source__multiple_outputs%29)
[8.2.3 Scribble vs. Pollen](https://docs.racket-lang.org/pollen/fourth-tutorial.html#%28part._.Scribble_vs__.Pollen%29)
[8.3 Making a multiple-output project](https://docs.racket-lang.org/pollen/fourth-tutorial.html#%28part._.Making_a_multiple-output_project%29)
[8.3.1 The poly output type](https://docs.racket-lang.org/pollen/fourth-tutorial.html#%28part._.The_poly_output_type%29)
[8.3.2 Poly sources in the project server](https://docs.racket-lang.org/pollen/fourth-tutorial.html#%28part._.Poly_sources_in_the_project_server%29)
[8.3.3 Adding output targets for poly sources](https://docs.racket-lang.org/pollen/fourth-tutorial.html#%28part._.Adding_output_targets_for_poly_sources%29)
[8.3.3.1 Using the setup submodule](https://docs.racket-lang.org/pollen/fourth-tutorial.html#%28part._.Using_the_setup_submodule%29)
[8.3.4 Adding support for another output format](https://docs.racket-lang.org/pollen/fourth-tutorial.html#%28part._.Adding_support_for_another_output_format%29)
[8.3.4.1 Adding a template for .txt](https://docs.racket-lang.org/pollen/fourth-tutorial.html#%28part._.Adding_a_template_for__txt%29)
[8.3.4.2 Branching tag functions](https://docs.racket-lang.org/pollen/fourth-tutorial.html#%28part._.Branching_tag_functions%29)
[8.3.5 Adding support for LaTeX output](https://docs.racket-lang.org/pollen/fourth-tutorial.html#%28part._.Adding_support_for_.La.Te.X_output%29)
[8.3.6 Adding support for PDF output](https://docs.racket-lang.org/pollen/fourth-tutorial.html#%28part._.Adding_support_for_.P.D.F_output%29)
[8.4 Using raco pollen render with poly sources](https://docs.racket-lang.org/pollen/fourth-tutorial.html#%28part._raco-pollen-render-poly%29)
[8.5 Fourth tutorial complete](https://docs.racket-lang.org/pollen/fourth-tutorial.html#%28part._.Fourth_tutorial_complete%29)

[9 Mini tutorials](https://docs.racket-lang.org/pollen/mini-tutorial.html)
[9.1 Syntax highlighting](https://docs.racket-lang.org/pollen/mini-tutorial.html#%28part._.Syntax_highlighting%29)
[9.1.1 Using Pygments with Pollen](https://docs.racket-lang.org/pollen/mini-tutorial.html#%28part._pygments-with-pollen%29)
[9.1.2 Using Highlight.js with Pollen](https://docs.racket-lang.org/pollen/mini-tutorial.html#%28part._.Using_.Highlight_js_with_.Pollen%29)
[9.2 Math typesetting with MathJax](https://docs.racket-lang.org/pollen/mini-tutorial.html#%28part._.Math_typesetting_with_.Math.Jax%29)

[10 Using raco pollen](https://docs.racket-lang.org/pollen/raco-pollen.html)
[10.1 Making sure raco pollen works](https://docs.racket-lang.org/pollen/raco-pollen.html#%28part._.Making_sure_raco_pollen_works%29)
[10.2 raco pollen](https://docs.racket-lang.org/pollen/raco-pollen.html#%28part._raco_pollen%29)
[10.3 raco pollen help](https://docs.racket-lang.org/pollen/raco-pollen.html#%28part._raco_pollen_help%29)
[10.4 raco pollen start](https://docs.racket-lang.org/pollen/raco-pollen.html#%28part._raco_pollen_start%29)
[10.5 raco pollen render](https://docs.racket-lang.org/pollen/raco-pollen.html#%28part._raco_pollen_render%29)
[10.6 raco pollen publish](https://docs.racket-lang.org/pollen/raco-pollen.html#%28part._raco_pollen_publish%29)
[10.7 raco pollen setup](https://docs.racket-lang.org/pollen/raco-pollen.html#%28part._raco_pollen_setup%29)
[10.8 raco pollen reset](https://docs.racket-lang.org/pollen/raco-pollen.html#%28part._raco_pollen_reset%29)
[10.9 raco pollen version](https://docs.racket-lang.org/pollen/raco-pollen.html#%28part._raco_pollen_version%29)
[10.10 The POLLEN environment variable](https://docs.racket-lang.org/pollen/raco-pollen.html#%28part._.The_.P.O.L.L.E.N_environment_variable%29)
[10.11 Logging & the PLTSTDERR environment variable](https://docs.racket-lang.org/pollen/raco-pollen.html#%28part._.Logging___the_.P.L.T.S.T.D.E.R.R_environment_variable%29)

[11 File formats](https://docs.racket-lang.org/pollen/File_formats.html)
[11.1 Source formats](https://docs.racket-lang.org/pollen/File_formats.html#%28part._.Source_formats%29)
[11.1.1 Command syntax using ◊](https://docs.racket-lang.org/pollen/File_formats.html#%28part._.Command_syntax_using_~e2~97~8a%29)
[11.1.2 Any command is valid](https://docs.racket-lang.org/pollen/File_formats.html#%28part._.Any_command_is_valid%29)
[11.1.3 Standard exports](https://docs.racket-lang.org/pollen/File_formats.html#%28part._.Standard_exports%29)
[11.1.4 Custom exports](https://docs.racket-lang.org/pollen/File_formats.html#%28part._.Custom_exports%29)
[11.1.5 The "pollen.rkt" file](https://docs.racket-lang.org/pollen/File_formats.html#%28part._.The__pollen_rkt__file%29)
[11.1.6 Preprocessor (.pp extension)](https://docs.racket-lang.org/pollen/File_formats.html#%28part._.Preprocessor___pp_extension_%29)
[11.1.7 Markdown (.pmd extension)](https://docs.racket-lang.org/pollen/File_formats.html#%28part._.Markdown___pmd_extension_%29)
[11.1.8 Markup (.pm extension)](https://docs.racket-lang.org/pollen/File_formats.html#%28part._.Markup___pm_extension_%29)
[11.1.9 Pagetree (.ptree extension)](https://docs.racket-lang.org/pollen/File_formats.html#%28part._.Pagetree____ptree_extension_%29)
[11.2 Utility formats](https://docs.racket-lang.org/pollen/File_formats.html#%28part._.Utility_formats%29)
[11.2.1 Scribble (.scrbl extension)](https://docs.racket-lang.org/pollen/File_formats.html#%28part._.Scribble____scrbl_extension_%29)
[11.2.2 Null (.p extension)](https://docs.racket-lang.org/pollen/File_formats.html#%28part._.Null___p_extension_%29)
[11.3 Escaping output-file extensions within source-file names](https://docs.racket-lang.org/pollen/File_formats.html#%28part._.Escaping_output-file_extensions_within_source-file_names%29)

[12 Pollen command syntax](https://docs.racket-lang.org/pollen/pollen-command-syntax.html)
[12.1 The golden rule](https://docs.racket-lang.org/pollen/pollen-command-syntax.html#%28part._.The_golden_rule%29)
[12.2 The lozenge (◊)](https://docs.racket-lang.org/pollen/pollen-command-syntax.html#%28part._the-lozenge%29)
[12.2.1“But I don’t want to use the lozenge ...”](https://docs.racket-lang.org/pollen/pollen-command-syntax.html#%28part.__.But_.I_don_t_want_to_use_the_lozenge_____%29)
[12.2.2 Lozenge helpers](https://docs.racket-lang.org/pollen/pollen-command-syntax.html#%28part._.Lozenge_helpers%29)
[12.2.2.1 How MB types the lozenge](https://docs.racket-lang.org/pollen/pollen-command-syntax.html#%28part._.How_.M.B_types_the_lozenge%29)
[12.2.2.2 DrRacket toolbar button](https://docs.racket-lang.org/pollen/pollen-command-syntax.html#%28part._.Dr.Racket_toolbar_button%29)
[12.2.2.3 DrRacket key shortcut](https://docs.racket-lang.org/pollen/pollen-command-syntax.html#%28part._.Dr.Racket_key_shortcut%29)
[12.2.2.4 AHK script for Windows](https://docs.racket-lang.org/pollen/pollen-command-syntax.html#%28part._.A.H.K_script_for_.Windows%29)
[12.2.2.5 Emacs script](https://docs.racket-lang.org/pollen/pollen-command-syntax.html#%28part._.Emacs_script%29)
[12.2.2.6 Emacs input method](https://docs.racket-lang.org/pollen/pollen-command-syntax.html#%28part._.Emacs_input_method%29)
[12.2.2.7 Vim (and Evil) digraph sequence](https://docs.racket-lang.org/pollen/pollen-command-syntax.html#%28part._.Vim__and_.Evil__digraph_sequence%29)
[12.2.2.8 Compose key](https://docs.racket-lang.org/pollen/pollen-command-syntax.html#%28part._.Compose_key%29)
[12.3 The two command styles: Pollen style & Racket style](https://docs.racket-lang.org/pollen/pollen-command-syntax.html#%28part._the-two-command-styles%29)
[12.3.1 The command name](https://docs.racket-lang.org/pollen/pollen-command-syntax.html#%28part._.The_command_name%29)
[12.3.1.1 Invoking tag functions](https://docs.racket-lang.org/pollen/pollen-command-syntax.html#%28part._.Invoking_tag_functions%29)
[12.3.1.2 Invoking other functions](https://docs.racket-lang.org/pollen/pollen-command-syntax.html#%28part._.Invoking_other_functions%29)
[12.3.1.3 Inserting the value of a variable](https://docs.racket-lang.org/pollen/pollen-command-syntax.html#%28part._.Inserting_the_value_of_a_variable%29)
[12.3.1.4 Inserting metas](https://docs.racket-lang.org/pollen/pollen-command-syntax.html#%28part._.Inserting_metas%29)
[12.3.1.5 Retrieving metas](https://docs.racket-lang.org/pollen/pollen-command-syntax.html#%28part._.Retrieving_metas%29)
[12.3.1.6 Inserting a comment](https://docs.racket-lang.org/pollen/pollen-command-syntax.html#%28part._.Inserting_a_comment%29)
[12.3.2 The Racket arguments](https://docs.racket-lang.org/pollen/pollen-command-syntax.html#%28part._.The_.Racket_arguments%29)
[12.3.3 The text body](https://docs.racket-lang.org/pollen/pollen-command-syntax.html#%28part._the-text-body%29)
[12.4 Embedding character entities](https://docs.racket-lang.org/pollen/pollen-command-syntax.html#%28part._.Embedding_character_entities%29)
[12.5 Adding Pollen-style commands to a Racket file](https://docs.racket-lang.org/pollen/pollen-command-syntax.html#%28part._.Adding_.Pollen-style_commands_to_a_.Racket_file%29)
[12.6 Further reading](https://docs.racket-lang.org/pollen/pollen-command-syntax.html#%28part._.Further_reading%29)

[13 Programming Pollen](https://docs.racket-lang.org/pollen/programming-pollen.html)
[13.1 Tag functions](https://docs.racket-lang.org/pollen/programming-pollen.html#%28part._.Tag_functions%29)
[13.1.1 Tag-function syntax](https://docs.racket-lang.org/pollen/programming-pollen.html#%28part._.Tag-function_syntax%29)
[13.1.2 Point of no return](https://docs.racket-lang.org/pollen/programming-pollen.html#%28part._.Point_of_no_return%29)
[13.1.3 Multiple input values & rest arguments](https://docs.racket-lang.org/pollen/programming-pollen.html#%28part._.Multiple_input_values___rest_arguments%29)
[13.1.4 Returning an X-expression](https://docs.racket-lang.org/pollen/programming-pollen.html#%28part._.Returning_an_.X-expression%29)
[13.1.5 Using variables within strings](https://docs.racket-lang.org/pollen/programming-pollen.html#%28part._.Using_variables_within_strings%29)
[13.1.6 Parsing attributes](https://docs.racket-lang.org/pollen/programming-pollen.html#%28part._.Parsing_attributes%29)

[14 Module reference](https://docs.racket-lang.org/pollen/Module_reference.html)
[14.1 Cache](https://docs.racket-lang.org/pollen/Cache.html)
[14.1.1 Preloading and reseting](https://docs.racket-lang.org/pollen/Cache.html#%28part._.Preloading_and_reseting%29)
[14.1.2 Disabling the cache](https://docs.racket-lang.org/pollen/Cache.html#%28part._.Disabling_the_cache%29)
[14.1.3 Scope of dependency tracking](https://docs.racket-lang.org/pollen/Cache.html#%28part._.Scope_of_dependency_tracking%29)
[14.1.4 Functions](https://docs.racket-lang.org/pollen/Cache.html#%28part._cache._.Functions%29)
[14.2 Core](https://docs.racket-lang.org/pollen/Core.html)
[14.2.1 Metas](https://docs.racket-lang.org/pollen/Core.html#%28part._.Metas%29)
[14.2.2 Splicing](https://docs.racket-lang.org/pollen/Core.html#%28part._.Splicing%29)
[14.2.3 Data helpers](https://docs.racket-lang.org/pollen/Core.html#%28part._.Data_helpers%29)
[14.2.4 Parameters](https://docs.racket-lang.org/pollen/Core.html#%28part._core%29)
[14.3 Decode](https://docs.racket-lang.org/pollen/Decode.html)
[14.4 File](https://docs.racket-lang.org/pollen/file-types.html)
[14.5 Pagetree](https://docs.racket-lang.org/pollen/Pagetree.html)
[14.5.1 Making pagetrees with a source file](https://docs.racket-lang.org/pollen/Pagetree.html#%28part._.Making_pagetrees_with_a_source_file%29)
[14.5.2 Making pagetrees by hand](https://docs.racket-lang.org/pollen/Pagetree.html#%28part._.Making_pagetrees_by_hand%29)
[14.5.3 Nesting pagetrees](https://docs.racket-lang.org/pollen/Pagetree.html#%28part._.Nesting_pagetrees%29)
[14.5.4 The automatic pagetree](https://docs.racket-lang.org/pollen/Pagetree.html#%28part._.The_automatic_pagetree%29)
[14.5.5 Using pagetrees for navigation](https://docs.racket-lang.org/pollen/Pagetree.html#%28part._.Using_pagetrees_for_navigation%29)
[14.5.6 Using "index.ptree" in the dashboard](https://docs.racket-lang.org/pollen/Pagetree.html#%28part._.Using__index_ptree__in_the_dashboard%29)
[14.5.7 Using pagetrees with raco pollen render](https://docs.racket-lang.org/pollen/Pagetree.html#%28part._.Using_pagetrees_with_raco_pollen_render%29)
[14.5.8 Functions](https://docs.racket-lang.org/pollen/Pagetree.html#%28part._.Functions%29)
[14.5.8.1 Predicates & validation](https://docs.racket-lang.org/pollen/Pagetree.html#%28part._.Predicates___validation%29)
[14.5.8.2 Navigation](https://docs.racket-lang.org/pollen/Pagetree.html#%28part._.Navigation%29)
[14.5.8.3 Utilities](https://docs.racket-lang.org/pollen/Pagetree.html#%28part._.Utilities%29)
[14.6 Render](https://docs.racket-lang.org/pollen/Render.html)
[14.7 Setup](https://docs.racket-lang.org/pollen/Setup.html)
[14.7.1 How to override setup values](https://docs.racket-lang.org/pollen/Setup.html#%28part._setup-overrides%29)
[14.7.2 Values](https://docs.racket-lang.org/pollen/Setup.html#%28part._.Values%29)
[14.7.3 Parameters](https://docs.racket-lang.org/pollen/Setup.html#%28part._.Parameters%29)
[14.8 Tag](https://docs.racket-lang.org/pollen/Tag.html)
[14.9 Template](https://docs.racket-lang.org/pollen/Template.html)
[14.9.1 HTML](https://docs.racket-lang.org/pollen/Template.html#%28part._.H.T.M.L%29)
[14.10 Top](https://docs.racket-lang.org/pollen/Top.html)

[15 Unstable module reference](https://docs.racket-lang.org/pollen/Unstable_module_reference.html)
[15.1 Pygments](https://docs.racket-lang.org/pollen/Pygments.html)
[15.2 Typography](https://docs.racket-lang.org/pollen/Typography.html)
[15.3 Convert](https://docs.racket-lang.org/pollen/Convert.html)

[16 Acknowledgments](https://docs.racket-lang.org/pollen/Acknowledgments.html)

[17 License & source code](https://docs.racket-lang.org/pollen/License___source_code.html)

[18 Version notes (3.2.4581.976)](https://docs.racket-lang.org/pollen/version-notes.html)
[18.1 What the version number means](https://docs.racket-lang.org/pollen/version-notes.html#%28part._.What_the_version_number_means%29)
[18.2 Source code](https://docs.racket-lang.org/pollen/version-notes.html#%28part._.Source_code%29)
[18.3 Development policy](https://docs.racket-lang.org/pollen/version-notes.html#%28part._.Development_policy%29)
[18.4 Changelog](https://docs.racket-lang.org/pollen/version-notes.html#%28part._.Changelog%29)
[18.4.1 Version 3.2](https://docs.racket-lang.org/pollen/version-notes.html#%28part._.Version_3_2%29)
[18.4.2 Version 3.1](https://docs.racket-lang.org/pollen/version-notes.html#%28part._.Version_3_1%29)
[18.4.3 Version 3.0](https://docs.racket-lang.org/pollen/version-notes.html#%28part._.Version_3_0%29)
[18.4.4 Version 2.2](https://docs.racket-lang.org/pollen/version-notes.html#%28part._.Version_2_2%29)
[18.4.5 Version 2.1](https://docs.racket-lang.org/pollen/version-notes.html#%28part._.Version_2_1%29)
[18.4.6 Version 2.0](https://docs.racket-lang.org/pollen/version-notes.html#%28part._.Version_2_0%29)
[18.4.7 Version 1.5](https://docs.racket-lang.org/pollen/version-notes.html#%28part._.Version_1_5%29)
[18.4.8 Version 1.4](https://docs.racket-lang.org/pollen/version-notes.html#%28part._.Version_1_4%29)
[18.4.9 Version 1.3](https://docs.racket-lang.org/pollen/version-notes.html#%28part._.Version_1_3%29)
[18.4.10 Version 1.2](https://docs.racket-lang.org/pollen/version-notes.html#%28part._.Version_1_2%29)
[18.4.11 Version 1.1](https://docs.racket-lang.org/pollen/version-notes.html#%28part._.Version_1_1%29)
[18.4.12 Version 1.0](https://docs.racket-lang.org/pollen/version-notes.html#%28part._.Version_1_0%29)

[Index](https://docs.racket-lang.org/pollen/doc-index.html)

[top](https://docs.racket-lang.org/index.html "up to the documentation top")[contents](javascript:void(0); "show/hide table of contents")← prev[up](https://docs.racket-lang.org/index.html "up to the documentation top")[next →](https://docs.racket-lang.org/pollen/Installation.html "forward to \"1 Installation\"")
