require 'test_helper'

class EvaluationsControllerTest < ActionDispatch::IntegrationTest
  def setup
    @series = create :series, exercise_count: 2, deadline: DateTime.now + 4.hours
    @exercises = @series.exercises
    @users = (0..2).map { |_| create :user }
    @users.each do |user|
      user.enrolled_courses << @series.course
      @exercises.each do |ex|
        create :submission, exercise: ex, user: user, course: @series.course, status: :correct
      end
    end
    @course_admin = create(:staff)
    @course_admin.administrating_courses << @series.course
    sign_in @course_admin
  end

  test 'Create session via wizard page' do
    post evaluations_path, params: {
      evaluation: {
        series_id: @series.id,
        deadline: DateTime.now + 4.days
      }
    }
    @series.evaluation.update(users: @users)

    assert_response :redirect
    assert_equal @users.count * @exercises.count, @series.evaluation.feedbacks.count
  end

  test 'Can remove user from feedback' do
    post evaluations_path, params: {
      evaluation: {
        series_id: @series.id,
        deadline: DateTime.now + 4.days
      }
    }
    @series.evaluation.update(users: @users)

    assert_response :redirect
    assert_equal @users.count * @exercises.count, @series.evaluation.feedbacks.count

    post remove_user_evaluation_path(@series.evaluation, user_id: @users.first.id, format: :js)
    assert_equal (@users.count - 1) * @exercises.count, @series.evaluation.feedbacks.count
  end

  test 'Can add user to feedback' do
    post evaluations_path, params: {
      evaluation: {
        series_id: @series.id,
        deadline: DateTime.now + 4.days
      }
    }
    @series.evaluation.update(users: @users)

    assert_response :redirect
    assert_equal @users.count * @exercises.count, @series.evaluation.feedbacks.count

    user = create :user
    user.enrolled_courses << @series.course

    post add_user_evaluation_path(@series.evaluation, user_id: user.id, format: :js)
    assert_equal (@users.count + 1) * @exercises.count, @series.evaluation.feedbacks.count
  end

  test "Can update a feedback's completed status" do
    post evaluations_path, params: {
      evaluation: {
        series_id: @series.id,
        deadline: DateTime.now + 4.days
      }
    }
    @series.evaluation.update(users: @series.course.enrolled_members)

    random_feedback = @series.evaluation.feedbacks.sample
    assert_not_nil random_feedback

    patch evaluation_feedback_path(@series.evaluation, random_feedback), params: { feedback: { completed: true } }

    random_feedback.reload
    assert_equal true, random_feedback.completed, 'completed should have been set to true'

    patch evaluation_feedback_path(@series.evaluation, random_feedback), params: { feedback: { completed: true } }

    random_feedback.reload
    assert_equal true, random_feedback.completed, 'marking complete should be idempotent'

    patch evaluation_feedback_path(@series.evaluation, random_feedback), params: { feedback: { completed: false } }

    random_feedback.reload
    assert_equal false, random_feedback.completed, 'completed should have been set to false'
  end

  test 'Notifications should be made when a feedback is released' do
    post evaluations_path, params: {
      evaluation: { series_id: @series.id, deadline: DateTime.now + 4.days }
    }
    evaluation = @series.evaluation
    evaluation.update(users: @series.course.enrolled_members)
    evaluation.update(released: false)

    feedbacks = evaluation.feedbacks.decided.includes(:submission)
    feedbacks.each do |feedback|
      # Annotation bound to Feedback
      evaluation.annotations.create(submission: feedback.submission, annotation_text: Faker::Lorem.sentences(number: 2), line_nr: 0, user: @course_admin)

      # Normal annotation
      Annotation.create(submission: feedback.submission, annotation_text: Faker::Lorem.sentences(number: 2), line_nr: 0, user: @course_admin)
    end
    assert_equal feedbacks.count, Notification.all.count, 'only notifications for the annotations without a feedback session'

    evaluation.feedbacks.each do |feedback|
      feedback.update(completed: true)
    end
    assert_equal feedbacks.count, Notification.all.count, 'no new notification should be made upon completing a feedback'

    evaluation.update(released: true)

    assert_equal feedbacks.count + @users.count, Notification.all.count, 'A new notification per user should be made upon releasing a feedback session, along with keeping the notifications made for annotations without a feedback session'
  end

  test 'non released annotations are not queryable' do
    post evaluations_path, params: {
      evaluation: {
        series_id: @series.id,
        deadline: DateTime.now + 4.days
      }
    }
    evaluation = @series.evaluation
    evaluation.update(users: @series.course.enrolled_members)
    evaluation.update(released: false)

    feedbacks = evaluation.feedbacks.decided.includes(:submission)
    feedbacks.each do |feedback|
      # Annotation bound to Feedback
      evaluation.annotations.create(submission: feedback.submission, annotation_text: Faker::Lorem.sentences(number: 2), line_nr: 0, user: @course_admin)

      # Normal annotation
      Annotation.create(submission: feedback.submission, annotation_text: Faker::Lorem.sentences(number: 2), line_nr: 0, user: @course_admin)
    end

    student = @users.sample
    assert_not_nil student
    picked_submission = evaluation.feedbacks.joins(:evaluation_user).where(evaluation_users: { user: student }).decided.sample.submission

    get submission_annotations_path(picked_submission, format: :json)
    json_response = JSON.parse(@response.body)
    assert_equal 2, json_response.size, 'Course admin should be able to see unreleased submissions'

    sign_in student

    assert_equal student, picked_submission.user
    get submission_annotations_path(picked_submission, format: :json)

    json_response = JSON.parse(@response.body)
    assert_equal 1, json_response.size, 'Only one annotation is visible here, since the feedback session is unreleased'

    evaluation.update(released: true)

    get submission_annotations_path(picked_submission, format: :json)

    json_response = JSON.parse(@response.body)
    assert_equal 2, json_response.size, 'Both annotations are visible, as the feedback session is released'

    random_unauthorized_student = create :student
    sign_in random_unauthorized_student

    get submission_annotations_path(picked_submission, format: :json)

    json_response = JSON.parse(@response.body)
    assert_equal 0, json_response.size, 'Non authorized users can not query for annotations on a submission that is not their own'

    sign_out random_unauthorized_student

    get submission_annotations_path(picked_submission, format: :json)

    json_response = JSON.parse(@response.body)
    assert_equal 0, json_response.size, 'Non logged in users may not query the annotations of a submission'
  end

  test 'feedback page only available for course admins' do
    post evaluations_path, params: {
      evaluation: {
        series_id: @series.id,
        deadline: DateTime.now + 4.days
      }
    }
    evaluation = @series.evaluation
    evaluation.update(users: @series.course.enrolled_members)
    random_feedback = evaluation.feedbacks.decided.sample

    get evaluation_feedback_path(evaluation, random_feedback)

    assert_response :success

    sign_out @course_admin

    # No log in
    get evaluation_feedback_path(evaluation, random_feedback)
    assert_response :redirect # Redirect to sign in page

    random_user = @users.sample
    assert_not random_user.admin_of?(@series.course)

    sign_in random_user
    get evaluation_feedback_path(evaluation, random_feedback)
    assert_response :redirect # Redirect to sign in page
  end

  test 'When a feedback session gets deleted, all the annotations created should be unset & therefor released' do
    post evaluations_path, params: {
      evaluation: { series_id: @series.id,
                    deadline: DateTime.now + 4.days }
    }
    evaluation = @series.evaluation
    evaluation.update(users: @series.course.enrolled_members)
    annotations = []
    evaluation.feedbacks.decided.each do |feedback|
      annotations << feedback.submission.annotations.create(evaluation: evaluation, user: @course_admin, annotation_text: Faker::Lorem.sentences(number: 3), line_nr: 0)
    end

    assert_not_empty annotations
    evaluation.destroy

    annotations.each do |annotation|
      annotation.reload
      assert_nil annotation.evaluation

      get submission_annotations_path(annotation.submission, format: :json)
      json_response = JSON.parse(@response.body)
      assert_equal 1, json_response.size, 'The one annotation is visible here, since the feedback session is deleted'
    end
  end

  test 'When there is already a feedback session for this series, we should redirect to the ready made one when a user wants to create a new one' do
    post evaluations_path, params: {
      evaluation: { series_id: @series.id,
                    deadline: DateTime.now + 4.days }
    }

    evaluation_count = Evaluation.where(series: @series).count

    evaluation = @series.evaluation
    assert_not_nil evaluation

    get new_evaluation_path(series_id: @series.id)
    assert_response :redirect

    post evaluations_path, params: {
      evaluation: { series_id: @series,
                    deadline: DateTime.now + 4.days,
                    users: @users.map(&:id),
                    exercises: @exercises.map(&:id) }
    }
    assert_response :redirect

    assert_equal evaluation_count, Evaluation.where(series: @series).count, 'No new feedback sessions should be made for this series'

    sign_out @course_admin
    get new_evaluation_path(series_id: @series.id)
    assert_response :redirect
  end

  test 'When there is no previous feedback session for this series, we can query the wizard' do
    get new_evaluation_path(series_id: @series.id)
    assert_response :success

    sign_out @course_admin
    get new_evaluation_path(series_id: @series.id)
    assert_response :redirect
  end

  test 'Edit page for a feedback session is only available for course admins' do
    post evaluations_path, params: {
      evaluation: {
        series_id: @series.id,
        deadline: DateTime.now + 4.days
      }
    }
    random_student = create :student
    evaluation = @series.evaluation
    staff_member = create :staff
    @series.course.administrating_members << staff_member

    get edit_evaluation_path(evaluation)
    assert_response :success

    sign_out @course_admin
    get edit_evaluation_path(evaluation)
    assert_response :redirect

    sign_in random_student
    get edit_evaluation_path(evaluation)
    assert_response :redirect
    sign_out random_student

    assert_not_nil staff_member
    sign_in staff_member
    get edit_evaluation_path(evaluation)
    assert_response :success
  end

  test 'Feedback page should be available for a course admin, for each feedback with a submission' do
    post evaluations_path, params: {
      evaluation: {
        series_id: @series.id,
        deadline: DateTime.now + 4.days
      }
    }

    random_student = create :student
    student_from_evaluation = @users.sample
    assert_not student_from_evaluation.admin_of?(@series.course)
    evaluation = @series.evaluation
    staff_member = create :staff
    @series.course.administrating_members << staff_member

    evaluation.feedbacks.decided.each do |feedback|
      get evaluation_feedback_path(evaluation, feedback)
      assert_response :success
    end
    sign_out @course_admin

    sign_in staff_member
    evaluation.feedbacks.decided.each do |feedback|
      get evaluation_feedback_path(evaluation, feedback)
      assert_response :success
    end
    sign_out staff_member

    sign_in random_student
    evaluation.feedbacks.decided.each do |feedback|
      get evaluation_feedback_path(evaluation, feedback)
      assert_response :redirect
    end
    sign_out random_student

    sign_in student_from_evaluation
    evaluation.feedbacks.decided.each do |feedback|
      get evaluation_feedback_path(evaluation, feedback)
      assert_response :redirect
    end
    sign_out student_from_evaluation

    evaluation.feedbacks.decided.each do |feedback|
      get evaluation_feedback_path(evaluation, feedback)
      assert_response :redirect
    end
  end

  test 'Show page should only be available to zeus and course admins' do
    post evaluations_path, params: {
      evaluation: {
        series_id: @series.id,
        deadline: DateTime.now + 4.days
      }
    }

    evaluation = @series.evaluation
    random_student = create :student
    student_from_evaluation = @users.sample
    assert_not student_from_evaluation.admin_of?(@series.course)
    staff_member = create :staff
    @series.course.administrating_members << staff_member

    [@course_admin, staff_member].each do |person|
      sign_in person
      get evaluation_path(evaluation)
      assert_response :success, 'Should get access since the user is not a student'
      sign_out person
    end

    [student_from_evaluation, random_student].each do |person|
      sign_in person
      get evaluation_path(evaluation)
      assert_response :redirect, 'Should not get access since the user is a student'
      sign_out person
    end
  end
end
