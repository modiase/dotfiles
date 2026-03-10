output "function_url" {
  value       = google_cloudfunctions2_function.amex_otp.url
  description = "URL of the amex-otp Cloud Function"
}

output "invoker_email" {
  value       = google_service_account.invoker.email
  description = "Email of the invoker service account"
}
