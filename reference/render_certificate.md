# Render a Journal-Ready Reproducibility Verification Certificate

Produces a publication-ready Markdown and/or standalone self-contained
HTML5 reproducibility verification certificate from an
`rcapsule_verification` audit result. Suitable for journal peer-review
supplements, Zenodo/OSF archival packages, and CI reproducibility gates.

## Usage

``` r
render_certificate(
  verification,
  output = NULL,
  format = c("both", "markdown", "html"),
  title = NULL
)
```

## Arguments

- verification:

  An `rcapsule_verification` object returned by
  [`verify_capsule()`](https://marcusharrisphd.com/rcapsule/reference/verify_capsule.md).

- output:

  Optional base output path (or exact file path when rendering a single
  format). When `format = "both"`, writes `<base>.md` and `<base>.html`.
  If `NULL`, returns rendered strings in memory without writing files.

- format:

  Output format: `"both"` (default), `"markdown"`, or `"html"`.

- title:

  Optional report title. Defaults to
  `"Reproducibility Verification Certificate: <project_name>"`.

## Value

An S3 object of class `rcapsule_certificate` with fields `markdown`,
`html`, `files` (named character vector of written paths), and
`verification`.

## Examples

``` r
tmp <- tempfile("rcapsule_cert_")
dir.create(tmp)
writeLines("write.csv(data.frame(a = 1:2), 'out.csv', row.names = FALSE)",
           file.path(tmp, "run.R"))
write.csv(data.frame(a = 1:2), file.path(tmp, "out.csv"), row.names = FALSE)
m <- create_capsule_manifest(tmp, outputs = "out.csv", seed = 1L)
v <- verify_capsule(m, path = tmp)
cert <- render_certificate(v, output = file.path(tmp, "certificate"))
cert$files
#>                                                      markdown 
#>   "/tmp/RtmpFZcrpm/rcapsule_cert_18fb75b6a1ba/certificate.md" 
#>                                                          html 
#> "/tmp/RtmpFZcrpm/rcapsule_cert_18fb75b6a1ba/certificate.html" 
unlink(tmp, recursive = TRUE)
```
